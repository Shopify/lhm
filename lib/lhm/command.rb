# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

module Lhm
  class Error < StandardError
  end

  module Command
    def run(&block)
      Lhm.logger.info "Starting run of class=#{self.class}"
      validate

      if block_given?
        before
        update_state_before_block
        block.call(self)
        after
        update_state_after_block
      else
        update_state_before_execute
        value = execute
        update_state_after_execute

        value
      end
    rescue => e
      Lhm.logger.error "Error in class=#{self.class}, reverting. exception=#{e.class} message=#{e.message}"
      update_state_when_revert
      
      revert
      raise
    end

    private

    def validate
    end

    def revert
    end

    # This method is called by the inherited class to update the state when there is an error raised
    # either during the execution of class.execute or inside a block being ran by the class.
    def update_state_when_revert
    end

    # This method is called by the inherited class before the class.execute method starts.
    def update_state_before_execute
    end

    # This method is called by the inherited class after the class.execute methods completes
    def update_state_after_execute
    end

    # This method is called before a block is ran by the inherited class.
    def update_state_before_block
    end

    # This method is called after a block is ran by the inherited class.
    def update_state_after_block
    end

    def execute
      raise NotImplementedError.new(self.class.name)
    end

    def before
    end

    def after
    end

    def error(msg)
      raise Error.new(msg)
    end
  end
end
