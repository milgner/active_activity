# frozen_string_literal: true

require 'active_activity/railtie'
require 'active_activity/runner'

require_relative 'test_activity'

module ActiveActivity
  RSpec.describe Runner do
    before(:each) { RedisBackend.new.reset }

    let(:config) { ActiveActivity.config }

    it 'starts and stops activities' do
      instance, cancellation = described_class.new(config)
      Concurrent::Promises.schedule(3).on_resolution { cancellation.resolve }
      expect_any_instance_of(TestActivity).to receive(:perform).with(kind_of(Concurrent::Cancellation)).and_call_original
      expect_any_instance_of(TestActivity).to receive(:stopping_now)

      Concurrent::Promises.schedule(0.1).on_resolution {
        TestActivity.start('arg1', 'arg2', kwarg1: 'foo', kwarg2: 'bar')
        TestActivity.stop('arg1', 'arg2', kwarg1: 'foo', kwarg2: 'bar')
      }
      instance.start
      # no proper way to test whether this really returns :(
      expect("I'm back").to be_truthy
    end
  end
end