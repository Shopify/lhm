# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt
require 'test_helper'

module UnitHelper
  LOG_EXPRESSION = /([\w]+),\s+\[([^\]\s]+)\s+#([^\]]+)]\s+(\w+)\s+--\s+(\w+)?:\s+(.+)/

  def fixture(name)
    File.read $fixtures.join(name)
  end

  def strip(sql)
    sql.strip.gsub(/\n */, "\n")
  end

  def log_expression_message(msg)
    msg.gsub(LOG_EXPRESSION) do |match|
      severity  = $1
      date      = $2
      pid       = $3
      label     = $4
      app       = $5
      message   = $6
    end
  end

  def progress
    {
      "state" => "copying",
      "version" => "3.4.2", 
      "source_table" => "foo", 
      "destination_table" => "lhmn_foo", 
      "throttler" => "None", 
      "table_switcher" => "LockedSwitcher", 
      "avg_row_length" => "20 bytes", 
      "estimated_bytes_copied" => 0, 
      "estimated_total_bytes" => 80000, 
      "completion_percentage" => "0% complete", 
      "estimated_copy_speed" => "0.0 bytes/sec", 
      "min_pk_key" => 1, 
      "max_pk_key" => 4000, 
      "rows_written" => 0
    }
  end
end
