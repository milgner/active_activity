# frozen_string_literal: true

require 'concurrent/edge/cancellation'
require 'concurrent/executor/cached_thread_pool'

require_relative 'redis_backend'

module ActiveActivity

  class Runner
    MAX_ACTIVE_TASKS = 255

    def initialize(config = {})
      @global_cancellation, @global_cancellation_origin = Concurrent::Cancellation.new
      @task_cancellations = {}
      # CachedThreadPool grows dynamically to fit the workload
      @executor = Concurrent::CachedThreadPool.new(name: 'active_activity', max_queue: 0, max_length: MAX_ACTIVE_TASKS)
      backend.ready
      trap('INT') { stop }
      trap('TERM') { stop }
    end

    # allows multi-assignment. Taken from Concurrent::Cancellation
    def to_ary
      [self, @global_cancellation_origin]
    end

    def start
      backend.running_activities.each do |args|
        start_activity(args)
      end
      backend.handle_new_activities(1, @global_cancellation) do |command, *args|
        case command
        when :start then start_activity(args)
        when :stop then stop_activity(args)
        end
      end
    end

    private

    def backend
      # TODO: make back-end configurable
      ActiveActivity.config.backend ||= RedisBackend.new
    end

    def stop_activity(args)
      key = cancellation_key(args)
      cancellation = @task_cancellations.delete(key)
      if cancellation.nil?
        $stderr << "Asked to stop activity which isn't running: #{key}"
        $stderr.flush
      else
        puts "Stopping activity #{key}"
        cancellation.resolve
      end
    end

    def start_activity(args)
      activity_cancellation, activity_cancellation_origin = Concurrent::Cancellation.new
      @task_cancellations[cancellation_key(args)] = activity_cancellation_origin
      activity_cancellation = activity_cancellation.join(@global_cancellation)
      @executor.post(activity_cancellation, args) do |activity_cancellation, args|
        instantiate_and_run(activity_cancellation, args)
      end
    end

    def instantiate_and_run(activity_cancellation, args)
      clazz, args, kwargs = args
      instance = clazz.constantize.new(*args, **kwargs)
      instance.perform(activity_cancellation)
      # TODO: handle errors & restart
    rescue => err
      binding.pry
      puts err.to_s
    end

    def cancellation_key(args)
      Array(args).map(&:to_s).join('|')
    end

    def stop
      # can't directly access from within signal handlers
      # this is a sub-optimal workaround
      Thread.new { @global_cancellation_origin.resolve }
    end
  end
end