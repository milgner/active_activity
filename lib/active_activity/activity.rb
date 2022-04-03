# frozen_string_literal: true

require 'active_support/concern'

module ActiveActivity
  # Include this module in your activity to give it its background-processing power
  module Activity
    extend ActiveSupport::Concern

    class_methods do
      # Starts the activity, passing the arguments to its constructor.
      # Only one instance of the activity can run for any given combination of arguments.
      # It is recommended to keep the method signature simple. You can use GlobalID to
      # pass in objects.
      def start(*args, **kwargs)
        ActiveActivity.config.backend.start_activity(self, args, kwargs)
      end

      # Arguments passed to `stop` must match those from the corresponding `start` call
      # or the system won't be able to match the activity
      def stop(*args, **kwargs)
        ActiveActivity.config.backend.stop_activity(self, args, kwargs)
      end
    end

    # a convevience method you can use in your activities if you don't need to
    # do any processing in your `perform` method itself. This is useful if your
    # activity uses a `Concurrent::TimerTask` or similar mechanisms.
    def wait_for_cancellation(cancellation)
      loop do
        cancellation.origin.to_future.wait!
        # not sure if spurious wakeups are a thing here,
        # but better to be safe than sorry
        break if cancellation.canceled?
      end
    end
  end
end
