# frozen_string_literal: true

require 'concurrent-ruby-edge/concurrent/edge/cancellation'
require 'concurrent-ruby/concurrent/executor/cached_thread_pool'

module ActiveActivity

  class Runner
    MAX_ACTIVE_TASKS = 255

    def initialize(config)
      @global_cancellation, @global_cancellation_origin = Concurrent::Cancellation.new
      @task_cancellations = {}
      # CachedThreadPool grows dynamically to fit the workload
      @executor = Concurrent::CachedThreadPool.new(name: 'active_activity', max_queue: 0).tap { |e| e.max_length = MAX_ACTIVE_TASKS }

      # TODO: make backend configurable
      @backend = RedisBackend.new(config.redis_url)

      trap('INT') { stop }
      trap('TERM') { stop }
    end

    def start
      @backend.running_activities.each do |args|
        start_activity(args)
      end
      @backend.handle_new_activities(1, @global_cancellation) do |command, *args|
        case command
        when :start then start_activity(args)
        when :stop then stop_activity(args)
        end
      end
    end

    private

    def stop_activity(args)
      key = cancellation_key(args)
      cancellation = @task_cancellations.delete(key)
      if cancellation.nil?
        $stderr << "Asked to stop activity which isn't runnig: #{key}"
      else
        $stdout << "Stopping activity #{key}"
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
    end

    def cancellation_key(args)
      args.map(&:to_s).join('|')
    end

    def stop
      @global_cancellation_origin.resolve
    end
  end
end