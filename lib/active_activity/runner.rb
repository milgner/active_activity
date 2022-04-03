# frozen_string_literal: true

require 'concurrent/edge/cancellation'
require 'concurrent/executor/cached_thread_pool'

require_relative 'redis_backend'
require_relative 'logging'

module ActiveActivity
  # Responsible for actually executing activities
  # It uses a backend which is responsible for storing information about which activities are supposed to be running
  # and notifying about new activities
  class Runner
    include Logging
    MAX_ACTIVE_TASKS = 255

    def initialize(_config = {})
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
      shutdown
    end

    private

    def shutdown
      @executor.kill
      # No need to resolve all the cancellation origins because they're chained
      # to the global cancellation which has been triggered at this point
      @executor.wait_for_termination(5)
    end

    def backend
      # TODO: make back-end configurable
      @backend ||= ActiveActivity.config.backend&.dup || RedisBackend.new
    end

    def stop_activity(args)
      key = cancellation_key(args)
      cancellation = @task_cancellations.delete(key)
      if cancellation.nil?
        $stderr << "Asked to stop activity which isn't running: #{key}"
        $stderr.flush
      else
        msg = "Stopping activity #{key}"
        log_info(msg)
        cancellation.resolve
      end
    end

    def log_info(msg)
      if defined?(Rails)
        Rails.logger.info(msg)
      else
        puts msg
      end
    end

    def start_activity(args)
      key = cancellation_key(args)
      if @task_cancellations.key?(key)
        log_info("Activity already running, ignoring command to start again: #{key}")
        return
      end

      activity_cancellation = initialize_cancellation(key)
      @executor.post(activity_cancellation, args) do |activity_cancellation, args|
        instantiate_and_run(activity_cancellation, args)
      end
    end

    def initialize_cancellation(key)
      activity_cancellation, activity_cancellation_origin = Concurrent::Cancellation.new
      @task_cancellations[key] = activity_cancellation_origin
      activity_cancellation.join(@global_cancellation)
    end

    def instantiate_and_run(activity_cancellation, args)
      class_name, args, kwargs = args
      run_until_stopped(activity_cancellation, class_name, args, kwargs)
    end

    def run_until_stopped(activity_cancellation, class_name, args, kwargs)
      log_info("Starting activity: #{class_name}[#{args}, #{kwargs}")
      loop do
        instance = instantiate(class_name, args, kwargs) || return
        instance.perform(activity_cancellation)
        # check if `perform` returned because of proper cancellation or because of some other error
        return if activity_cancellation.canceled?
      rescue StandardError => e
        msg = "Activity errored, going to restart: #{e}"
        log_error(msg)
      end
    end

    def instantiate(class_name, args, kwargs)
      clazz = class_name.constantize
      clazz.new(*args, **kwargs)
    rescue NameError => _e
      log_error("Failed to instantiate activity, the class does not exist anymore: #{class_name}")
      nil
    end

    def cancellation_key(args)
      Array(args).map(&:to_s).join('|')
    end

    def stop
      # can't directly access from within signal handlers
      # this is a sub-optimal workaround
      origin = @global_cancellation_origin
      Thread.new do
        origin.resolve
      end
    end
  end
end
