require File.expand_path(File.dirname(__FILE__)) + '/unit_helper'

describe 'Lhm.inline_allowed?' do
  # Unit specs don't load railties, so each spec defines a stand-in Rails with only `env`.
  def stub_rails_env(name)
    rails = Module.new
    rails.define_singleton_method(:env) { ActiveSupport::StringInquirer.new(name) }
    Object.const_set(:Rails, rails)
  end

  def reset_inline_setting
    Lhm.remove_class_variable(:@@inline_allowed) if Lhm.class_variable_defined?(:@@inline_allowed)
  end

  before(:each) do
    raise 'Rails is unexpectedly defined in unit specs' if defined?(Rails)
    reset_inline_setting
  end

  after(:each) do
    Object.send(:remove_const, :Rails) if defined?(Rails)
    reset_inline_setting
  end

  describe 'with no overrides' do
    it 'is true in development' do
      stub_rails_env('development')
      value(Lhm.inline_allowed?).must_equal true
    end

    it 'is true in test' do
      stub_rails_env('test')
      value(Lhm.inline_allowed?).must_equal true
    end

    it 'is false in production' do
      stub_rails_env('production')
      value(Lhm.inline_allowed?).must_equal false
    end

    it 'is false without Rails' do
      value(Lhm.inline_allowed?).must_equal false
    end
  end

  describe 'disallow_inline!' do
    it 'turns inlining off in development' do
      stub_rails_env('development')
      Lhm.disallow_inline!
      value(Lhm.inline_allowed?).must_equal false
    end

    it 'turns inlining off in test' do
      stub_rails_env('test')
      Lhm.disallow_inline!
      value(Lhm.inline_allowed?).must_equal false
    end
  end

  describe 'allow_inline!' do
    it 'turns inlining on in other environments' do
      stub_rails_env('ci')
      Lhm.allow_inline!
      value(Lhm.inline_allowed?).must_equal true
    end

    it 'turns inlining on without Rails' do
      Lhm.allow_inline!
      value(Lhm.inline_allowed?).must_equal true
    end
  end
end
