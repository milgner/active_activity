# frozen_string_literal: true

require 'redis' rescue LoadError

module ActiveActivity
  if defined?(Redis)
    # The main backend for production use via Redis
    #
    # It pushes requests to start and stop new jobs into the keys `start` and `stop`.
    # Once started, jobs are in the `running` key which is also used to start the system
    # back up after a shutdown.
    class RedisBackend
      KEY_PREFIX = 'active_activity.'
      DEFAULT_URL = 'redis://localhost:6379/2'

      def initialize(url = DEFAULT_URL)
        @redis = Redis.new(url: url)
      end

      def initialize_copy(orig)
        @redis = Redis.new(orig.redis_connection)
      end

      def redis_connection
        @redis_connection ||= @redis.connection.dup
      end

      # Invoked by the activity when it wants to start
      def start_activity(clazz, args = [], kwargs = {})
        encoded = encode('start', clazz, args, kwargs)
        @redis.rpush(key_name('command'), encoded)
      end

      def stop_activity(clazz, args = [], kwargs = {})
        encoded = encode('stop', clazz, args, kwargs)
        @redis.rpush(key_name('command'), encoded)
      end

      def reset
        @redis.del(running_key)
        @redis.del(key_name('command'))
      end

      def running_activities
        running = @redis.get(running_key)
        running ? JSON.parse(running) : []
      end

      def ready
        @redis.connected?
      end

      # Returns with information about a new job
      # @param cancellation [Concurrent::Cancellation] indicates that handling should stop
      # @param timeout [Fixnum] how often to check for cancellation (in seconds)
      # @yield [classname, args, kwargs]
      # @return [Array] array containing class name, args and kwargs
      def handle_new_activities(timeout, cancellation)
        loop do
          # FIXME: if this statement isn't there, redis gem will never return
          # either here or in the corresponding rpush
          puts ""
          key, new_activity = @redis.blpop(key_name('command'), timeout: timeout)
          return if cancellation.canceled?
          next if key.nil? # no new activities in this cycle

          args = decode(new_activity)
          yield *args

          update_running(args)
        end
      end

      private

      def update_running(args)
        cmd = args.shift
        updated_activities = if cmd == :start
                               running_activities + args
                             else
                               running_activities.tap { |a| a.delete(args) }
                             end
        @redis.set(running_key, JSON.dump(updated_activities))
      end

      def running_key
        @running_key ||= key_name('running')
      end

      # @return [Symbol] either :start or :stop
      def check_command(cmd)
        raise ArgumentError unless %w[start stop].include?(cmd)
        cmd.to_sym
      end

      def key_name(key)
        KEY_PREFIX + key
      end

      def decode(encoded)
        cmd, clazz, args, kwargs = JSON.parse(encoded).fetch_values('command', 'clazz', 'args', 'kwargs')
        [check_command(cmd), clazz, args, kwargs.with_indifferent_access]
      end

      def encode(command, clazz, args, kwargs)
        JSON.dump({
                    command: command,
                    clazz: clazz,
                    args: args,
                    kwargs: kwargs,
                    started_at: Time.current
                  })
      end
    end
  end
end
