module Lhm
  class Railtie < Rails::Railtie
    config.after_initialize do
      Lhm.execute_inline! if Lhm.inline_allowed?
    end
  end
end
