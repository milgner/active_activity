# frozen_string_literal: true

namespace :activities do
  desc 'Start processing your activities. Blocks until SIGINT / SIGTERM is received.'
  task run: :environment do
    ActiveActivity.setup

    runner = ActiveActivity::Runner.new(ActiveActivity.config)
    runner.start
    # TODO: find out why Ruby doesn't exit by itself
    # probably to do with the concurrent pool, but all of its tasks did shut down
    exit!
  end
end
