# frozen_string_literal: true

require 'active_support/concern'

module ActiveActivity
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
  end
end
