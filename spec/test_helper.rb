# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

if ENV['COV']
  require 'simplecov'
  SimpleCov.start
end

require 'minitest/autorun'
require 'minitest/spec'
require 'minitest/mock'
require 'mocha/minitest'
require 'pathname'
require 'lhm'

$project = Pathname.new(File.dirname(__FILE__) + '/..').cleanpath
$spec = $project.join('spec')
$fixtures = $spec.join('fixtures')

require 'active_record'
require 'mysql2'

logger = Logger.new STDOUT
logger.level = Logger::WARN
Lhm.logger = logger

def without_verbose(&block)
  old_verbose, $VERBOSE = $VERBOSE, nil
  yield
ensure
  $VERBOSE = old_verbose
end

def printer
  printer = Lhm::Printer::Base.new

  def printer.notify(*) ;end
  def printer.end(*) [] ;end

  printer
end

def throttler
  Lhm::Throttler::Time.new(:stride => 100)
end
