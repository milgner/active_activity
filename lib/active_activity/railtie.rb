# frozen_string_literal: true

require_relative 'runner'

module ActiveActivity
  class Railtie < ::Rails::Railtie
    rake_tasks do
      load 'active_activity/activity_tasks.rake'
    end

    config.to_prepare do
      ActiveActivity.setup
    end

    server do
      # in development mode, start the runner
      # but on production it should be a separate process
      next unless Rails.development?

      Thread.new do
        Rails.logger.info("[ActiveActivity] development environment detected, starting activity runner in server")
        ActiveActivity::Runner.new(ActiveActivity.config).start
      end
    end
  end
end