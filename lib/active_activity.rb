# frozen_string_literal: true

require 'active_support/configurable'
require 'active_support'
require 'active_support/core_ext'

require_relative 'active_activity/version'
require_relative 'active_activity/redis_backend'
require_relative 'active_activity/activity'

# Constantly-running background tasks
module ActiveActivity
  include ActiveSupport::Configurable

  class << self
    def setup
      config.backend ||= default_backend
    end

    private

    def default_backend
      raise 'No activity backend configured and no Redis available for default backend' unless defined?(RedisBackend)

      RedisBackend.new(config.redis_url).tap do |backend|
        # prevent it from starting anything left-over from previous tests
        backend.reset if defined?(Rails) && Rails.env.test?
      end
    end
  end
end

require 'active_activity/railtie' if defined?(Rails::Railtie)
