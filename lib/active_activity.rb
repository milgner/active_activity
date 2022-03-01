# frozen_string_literal: true

require_relative "active_activity/version"

# Constantly-running background tasks
module ActiveActivity
end

require 'active_activity/railtie' if defined?(Rails::Railtie)
