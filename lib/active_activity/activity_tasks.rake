# frozen_string_literal: true

namespace :activities do
  desc 'Start processing your activities. Blocks until SIGINT / SIGTERM is received.'
  task run: :environment do
    ActiveActivity.setup

    ActiveActivity::Runner.new(ActiveActivity.config).start
  end
end
