# frozen_string_literal: true

require 'active_activity/redis_backend'
require 'concurrent/edge/cancellation'

require_relative 'test_activity'

module ActiveActivity
  RSpec.describe RedisBackend do
    it 'instantiates based on a default URL' do
      redis_connection = subject.redis_connection
      expect(redis_connection).to be_a Hash
      expect(redis_connection[:host]).to eq 'localhost'
      expect(redis_connection[:port]).to eq 6379
      expect(redis_connection[:db]).to eq 2
    end


    describe '#handle_new_activities' do
      before(:all) { described_class.new.reset }

      let(:clazz) { TestActivity.to_s }
      let(:args) { ['arg1', 'arg2'] }
      let(:kwargs) { { kwarg1: 'foo', kwarg2: 'bar' } }

      it 'passes start and stop requests to block until the cancellation happens' do
        subject.start_activity(clazz, args, kwargs)

        cancellation, origin = Concurrent::Cancellation.new
        Concurrent::Promises.schedule(0.5).on_resolution { origin.resolve }
        Concurrent::Promises.schedule(0.3).on_resolution { subject.stop_activity(clazz, args, kwargs) }
        expect { |b| subject.handle_new_activities(0.1, cancellation, &b) }.to(
          yield_successive_args([:start, clazz, args, kwargs], [:stop, clazz, args, kwargs])
        )
      end
    end
  end
end
