# frozen_string_literal: true

module ActiveActivity
  if defined?(Redis)
    # The main backend for production use via Redis
    #
    # It pushes requests to start and stop new jobs into the keys `start` and `stop`.
    # Once started, jobs are in the `running` key which is also used to start the system
    # back up after a shutdown.
    class RedisBackend
      KEY_PREFIX = "active_activity."

      def initialize(url)
        @redis = Redis.new(url: url)
      end

      # Invoked by the activity when it wants to start
      def start_activity(clazz, args = [], kwargs = {})
        encoded = encode('start', clazz, args, kwargs)
        @redis.push(key_name('command'), encoded)
      end

      def running_activities
        @redis.get(key_name('running')) || []
      end

      # Returns with information about a new job
      # @param cancellation [Concurrent::Cancellation] indicates that handling should stop
      # @param timeout [Fixnum] how often to check for cancellation (in seconds)
      # @yield [classname, args, kwargs]
      # @return [Array] array containing class name, args and kwargs
      def handle_new_activities(timeout, cancellation)
        loop do
          key, new_activity = @redis.blpop(key_name('start'), key_name('stop'), timeout: interval_s)
          return if cancellation.canceled?
          next if key.nil? # no new activities in this cycle
          command = extract_command(key)
          yield command, *decode(new_activity)
        end
      end

      private

      # @return [Symbol] either :start or :stop
      def extract_command(key_name)
        cmd = /\.(\w+)$/.match(key_name)[1]
        raise ArgumentError unless %w[start stop].include?(cmd)
        cmd.to_sym
      end

      def key_name(key)
        KEY_PREFIX + key
      end

      def decode(encoded)
        JSON.parse(encoded).fetch_values('clazz', 'args', 'kwargs')
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
