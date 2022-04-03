# frozen_string_literal: true

module ActiveActivity
  # Convenience for logging
  module Logging
    def log_error(err)
      if defined?(Rails)
        Rails.logger.error(err)
      else
        warn(err)
      end
    end
  end
end
