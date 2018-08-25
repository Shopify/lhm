module Lhm
  class Timestamp
    def initialize(time)
      @time = time
    end

    def to_s
      @time.strftime "%Y%m%d%H%M%S"
    end
  end
end
