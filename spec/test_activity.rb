# frozen_string_literal: true

class TestActivity
  include ActiveActivity::Activity

  attr_reader :args, :kwargs

  def initialize(*args, **kwargs)
    @args = args
    @kwargs = kwargs
  end

  def perform(cancellation)
    loop do
      if cancellation.canceled?
        stopping_now
        break
      end
      working_still
      sleep 0.05
    end
  end

  def working_still
    # also for mocks
  end

  def stopping_now
    # only for detection via mock
  end
end
