# frozen_string_literal: true

begin
  require 'redis'
rescue StandardError
  LoadError
end

module ActiveActivity # rubocop:disable Style/Documentation
  if defined?(Redis)
    # The main backend for production use via Redis
    #
    # While it should be possible to implement other backends, Redis is the most practical
    # one for now as it provides both a way to store the information about which activities
    # are supposed to be running and a blocking read that returns when new commands are
    # queued.
    #
    # It pushes requests to start and stop new jobs into the key `command` (to ensure
    # they're processed in order of insertion).
    # Once started, jobs are added to the `running` key which is also used to start the
    # system back up after a shutdown.
    class RedisBackend
      KEY_PREFIX = 'active_activity.'
      DEFAULT_URL = 'redis://localhost:6379/' # 🤷 better to have some sensible default than none
      DEFAULT_DB = 0
      DEFAULT_DB_TESTS = 1

      def initialize(url = nil)
        url ||= determine_default_url
        @redis = Redis.new(url: url)
      end

      # helps to ensure that no two instances are using the same
      # Redis object as it would cause problems when one thread
      # wants to write while the other blocks while polling
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

      # mostly for testing purposes but might also be used to clean up
      # state if, for example an activity's class doesn't exist anymore
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
          key, new_activity = @redis.blpop(key_name('command'), timeout: timeout)
          break if cancellation.canceled?
          next if key.nil? # no new activities in this cycle

          args = decode(new_activity)
          yield(*args)

          update_running(args)
        end
      end

      private

      def update_running(args)
        cmd = args.shift
        updated_activities = if cmd == :start
                               running_activities + [args]
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
        raise ArgumentError unless %w[start stop].include?(cmd.to_s)

        cmd.to_sym
      end

      def key_name(key)
        KEY_PREFIX + key
      end

      def decode(encoded)
        cmd, clazz, args, kwargs = JSON.parse(encoded, symbolize_names: true).fetch_values(:command, :clazz, :args,
                                                                                           :kwargs)
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

      def determine_default_url
        ENV['REDIS_URL'].presence ||
          (DEFAULT_URL + environment_specific_database_number.to_s)
      end

      def environment_specific_database_number
        return DEFAULT_DB unless defined?(Rails) && Rails.env.test?

        DEFAULT_DB_TESTS
      end
    end
  else
    warn("Redis not loaded, Redis backend won't be available")
  end
end
