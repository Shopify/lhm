# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require 'lhm/command'
require 'lhm/migration'
require 'lhm/sql_helper'
require 'lhm/table'

module Lhm
  # Copies existing schema and applies changes using alter on the empty table.
  # `run` returns a Migration which can be used for the remaining process.
  class Migrator
    include Command
    include SqlHelper

    attr_reader :name, :statements, :connection, :conditions, :renames, :origin

    def initialize(table, connection = nil, options = {})
      @connection = connection
      @origin = table
      @name = table.destination_name
      @statements = []
      @renames = {}
      @options = options
    end

    # Alter a table with a custom statement
    #
    # @example
    #
    #   Lhm.change_table(:users) do |m|
    #     m.ddl("ALTER TABLE #{m.name} ADD COLUMN age INT(11)")
    #   end
    #
    # @param [String] statement SQL alter statement
    # @param [String] algorithm Algorithm that will be used in the DDL operation
    # @note
    #
    #   Don't write the table name directly into the statement. Use the #name
    #   getter instead, because the alter statement will be executed against a
    #   temporary table.
    #
    def ddl(statement, algorithm: nil)
      full_statement = algorithm ? "#{statement}, ALGORITHM=#{algorithm}" : statement
      statements << full_statement
    end

    # Add a column to a table
    #
    # @example
    #
    #   Lhm.change_table(:users) do |m|
    #     m.add_column(:comment, "VARCHAR(12) DEFAULT '0'")
    #   end
    #
    # @param [String] name Name of the column to add
    # @param [String] definition Valid SQL column definition
    # @param [String] algorithm Algorithm that will be used in the DDL operation
    def add_column(name, definition, algorithm: 'COPY')
      ddl('alter table `%s` add column `%s` %s' % [@name, name, definition], algorithm:)
    end

    # Change an existing column to a new definition
    #
    # @example
    #
    #   Lhm.change_table(:users) do |m|
    #     m.change_column(:comment, "VARCHAR(12) DEFAULT '0' NOT NULL")
    #   end
    #
    # @param [String] name Name of the column to change
    # @param [String] definition Valid SQL column definition
    def change_column(name, definition)
      if definition.match?(/^(DROP|SET) DEFAULT/i)
        ddl('alter table `%s` alter column `%s` %s' % [@name, name, definition])
      else
        ddl('alter table `%s` modify column `%s` %s' % [@name, name, definition])
      end
    end

    # Rename an existing column.
    #
    # @example
    #
    #   Lhm.change_table(:users) do |m|
    #     m.rename_column(:login, :username)
    #   end
    #
    # @param [String] old Name of the column to change
    # @param [String] nu New name to use for the column
    # @param [String] algorithm Algorithm that will be used in the DDL operation
    def rename_column(old, nu, algorithm: 'COPY')
      col = @origin.columns[old.to_s]

      definition = col[:type]

      definition += ' NOT NULL' unless col[:is_nullable] == "YES"
      definition += " DEFAULT #{@connection.quote(col[:column_default])}" if col[:column_default]
      definition += " COMMENT #{@connection.quote(col[:comment])}" if col[:comment]
      definition += " COLLATE #{@connection.quote(col[:collate])}" if col[:collate]

      ddl('alter table `%s` change column `%s` `%s` %s' % [@name, old, nu, definition], algorithm:)
      @renames[old.to_s] = nu.to_s
    end

    # Remove a column from a table
    #
    # @example
    #
    #   Lhm.change_table(:users) do |m|
    #     m.remove_column(:comment)
    #   end
    #
    # @param [String] name Name of the column to delete
    # @param [String] algorithm Algorithm that will be used in the DDL operation
    def remove_column(name, algorithm: 'COPY')
      ddl('alter table `%s` drop `%s`' % [@name, name], algorithm:)
    end

    # Add an index to a table
    #
    # @example
    #
    #   Lhm.change_table(:users) do |m|
    #     m.add_index(:comment)
    #     m.add_index([:username, :created_at])
    #     m.add_index("comment(10)")
    #   end
    #
    # @param [String, Symbol, Array<String, Symbol>] columns
    #   A column name given as String or Symbol. An Array of Strings or Symbols
    #   for compound indexes. It's possible to pass a length limit.
    # @param [String, Symbol] index_name
    #   Optional name of the index to be created
    def add_index(columns, index_name = nil)
      ddl(index_ddl(columns, false, index_name))
    end

    # Add a unique index to a table
    #
    # @example
    #
    #   Lhm.change_table(:users) do |m|
    #     m.add_unique_index(:comment)
    #     m.add_unique_index([:username, :created_at])
    #     m.add_unique_index("comment(10)")
    #   end
    #
    # @param [String, Symbol, Array<String, Symbol>] columns
    #   A column name given as String or Symbol. An Array of Strings or Symbols
    #   for compound indexes. It's possible to pass a length limit.
    # @param [String, Symbol] index_name
    #   Optional name of the index to be created
    def add_unique_index(columns, index_name = nil)
      ddl(index_ddl(columns, true, index_name))
    end

    # Remove an index from a table
    #
    # @example
    #
    #   Lhm.change_table(:users) do |m|
    #     m.remove_index(:comment)
    #     m.remove_index([:username, :created_at])
    #   end
    #
    # @param [String, Symbol, Array<String, Symbol>] columns
    #   A column name given as String or Symbol. An Array of Strings or Symbols
    #   for compound indexes.
    # @param [String, Symbol] index_name
    #   Optional name of the index to be removed
    def remove_index(columns, index_name = nil)
      columns = [columns].flatten.map(&:to_sym)
      from_origin = @origin.indices.find { |_, cols| cols.map(&:to_sym) == columns }
      index_name ||= from_origin[0] unless from_origin.nil?
      index_name ||= idx_name(@origin.name, columns)
      ddl('drop index `%s` on `%s`' % [index_name, @name])
    end

    # Filter the data that is copied into the new table by the provided SQL.
    # This SQL will be inserted into the copy directly after the "from"
    # statement - so be sure to use inner/outer join syntax and not cross joins.
    #
    # @example Add a conditions filter to the migration.
    #   Lhm.change_table(:sounds) do |m|
    #     m.filter("inner join users on users.`id` = sounds.`user_id` and sounds.`public` = 1")
    #   end
    #
    # @param [ String ] sql The sql filter.
    #
    # @return [ String ] The sql filter.
    def filter(sql)
      @conditions = sql
    end

    private

    def validate
      unless @connection.data_source_exists?(@origin.name)
        error("could not find origin table #{ @origin.name }")
      end

      unless @origin.satisfies_id_column_requirement?
        error('origin does not satisfy `id` key requirements')
      end

      dest = @origin.destination_name

      if @connection.data_source_exists?(dest)
        error("#{ dest } should not exist; not cleaned up from previous run?")
      end
    end

    def execute
      destination_create
      @statements.each do |stmt|
        @connection.execute(tagged(stmt))
      end
      Migration.new(@origin, destination_read, conditions, renames, Time.now, generated_column_names)
    end

    def generated_column_names
      @connection.columns(@origin.name).select(&:virtual?).map(&:name)
    end

    def destination_create
      original    = %{CREATE TABLE `#{ @origin.name }`}
      replacement = %{CREATE TABLE `#{ @origin.destination_name }`}
      stmt = @origin.ddl.gsub(original, replacement)

      if @options[:force_default_engine]
        stmt = stmt.sub(/ENGINE=\w+\s/, "")
      end

      @connection.execute(tagged(stmt))

      Lhm.logger.info("Created destination table #{@origin.destination_name}")
    end

    def destination_read
      Table.parse(@origin.destination_name, connection)
    end

    def index_ddl(cols, unique = nil, index_name = nil)
      assert_valid_idx_name(index_name)
      type = unique ? 'unique index' : 'index'
      index_name ||= idx_name(@origin.name, cols)
      parts = [type, index_name, @name, idx_spec(cols)]
      'create %s `%s` on `%s` (%s)' % parts
    end

    def assert_valid_idx_name(index_name)
      if index_name && !(index_name.is_a?(String) || index_name.is_a?(Symbol))
        raise ArgumentError, 'index_name must be a string or symbol'
      end
    end
  end
end
