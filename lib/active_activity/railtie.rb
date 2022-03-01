# frozen_string_literal: true

module ActiveActivity
  class Railtie < Rails::Railtie
    rake_tasks do
      load 'active_activity/activity_tasks.rake'
    end
  end
end