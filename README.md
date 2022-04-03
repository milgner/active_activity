# ActiveActivity

Run background activities until they're stopped.

ActiveJob is great for running one-off tasks. And there are several add-ons for periodic execution of jobs.
But there's no convenient way to easily run tasks that are supposed to be run indefinitely in the background
until stopped. This is what ActiveActivity is for.


### Difference from ActiveJob

Although it's possible to have jobs that re-enqueue themselves to simulate continuous activity, they produce
some corresponding overhead from queue management and might get a bit hacky to get right.
You'll also have to introduce your own semantics for stopping the loop and the corresponding implementation
will need to take care of avoiding race conditions.
Finally, one looses all state between each iteration which will have to be rebuilt each cycle.


### Example activities

- continuously reading and processing data from an API (i.e. Websocket)

## Requirements

The library utilises Redis for inter-process communication and persisting the desired state.
So you'll need a Redis server. I also decided that legacy projects are unlikely to adopt a new
library like this and made Ruby >=3.0 a prerequisite.

Most of the documentation assumes that you're running Rails but the code **should** also accommodate
other frameworks. Nonetheless, I decided to depend on the `active_support` gem for infrastructure
like `Concern` and it's `Configurable` module.

If you encounter problems using it in a non-Rails environment, let me know. Contributions welcome!


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'active_activity'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install active_activity


## Usage

Similar to Sidekiq, Que and other ActiveJob backends, you'll need to start a process which is responsible for
picking up und starting active activities.

Execute `rake active_activity:run` to start the process. This is only necessary in `production` mode, though:
in `development` mode, starting the server will also start a Thread with an activity runner.

### Redis configuration

Redis configuration will be taken from `REDIS_URL` or can be specified in a configuration block.
To separate data from other parts of your application, key names are prefixed with `active_activity.`.
If you want to use another Redis instance or database number, just configure it in an initializer.

```ruby
ActiveActivity.configure do |config|
  config.redis_url = 'redis://my-redis-server:6379/5'
end
```

If no `REDIS_URL` is present, the gem will try `redis://localhost:6379/0` to connect to Redis.

### Test Environment

To prevent mix-up of state between your development and test environments, `redis://localhost:6379/1` will
be used when no custom URL has been set and the gem detects it's running in a Rails test environment.
Just like in an actual environment, feel free to configure a different URL in your test setup.

Before tests, it will also reset the information about running activities during the setup phase.

### Writing Activities

Activities are regular classes that extend the `ActiveActivity::Activity` concern. This provides them with `start` 
and `stop` class methods that control whether the activity is running.

You'll need to implement these instance methods:

  - a constructor which receives all the arguments passed to `YourActivity.start`
  - a `perform` method which receives a [Cancellation](http://ruby-concurrency.github.io/concurrent-ruby/1.1.8/Concurrent/Cancellation.html)
object. While the library is responsible for allocating a thread for the activities' work, your activity has
to periodically check the cancellation for its `canceled?` state and abort the work if requested.

When reacting to a cancellation you can do some clean-up work before fully exiting, but it should be minimal
or you risk the thread being killed during that.

If the activity crashes while doing its work, it will be restarted automatically, but in a new instance.
So you can assume that `perform` is only invoked once on a given instance of the activity.

See `spec/test_activity.rb` for a minimalist dummy activity.


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/milgner/active_activity/issues.


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
