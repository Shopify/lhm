# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$:.unshift(lib) unless $:.include?(lib)

require 'lhm/version'

Gem::Specification.new do |s|
  s.name          = 'lhm-shopify'
  s.version       = Lhm::VERSION
  s.licenses      = ['BSD-3-Clause']
  s.platform      = Gem::Platform::RUBY
  s.authors       = ['SoundCloud', 'Shopify', 'Rany Keddo', 'Tobias Bielohlawek', 'Tobias Schmidt']
  s.email         = %q{database-engineering@shopify.com}
  s.summary       = %q{online schema changer for mysql}
  s.description   = %q{Migrate large tables without downtime by copying to a temporary table in chunks. The old table is not dropped. Instead, it is moved to timestamp_table_name for verification.}
  s.homepage      = %q{http://github.com/shopify/lhm}
  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_paths = ['lib']
  s.executables   = []
  s.metadata['allowed_push_host'] = "https://rubygems.org"

  s.required_ruby_version = '>= 3.0.0'

  s.add_dependency 'retriable', '>= 3.0.0'

  s.add_development_dependency 'activerecord'
  s.add_development_dependency 'minitest'
  s.add_development_dependency 'mocha'
  s.add_development_dependency 'after_do'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'mysql2'
  s.add_development_dependency 'trilogy'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'toxiproxy'
  s.add_development_dependency 'appraisal'
  s.add_development_dependency 'byebug'
  s.add_development_dependency 'ostruct'
  s.add_development_dependency 'logger'
end
