module Lhm
  class Railtie < Rails::Railtie
    initializer "lhm.test_setup" do
      if Rails.env.test? || Rails.env.development?
        Lhm.execute_inline! if Lhm.inline_allowed?
      end
    end
  end
end
