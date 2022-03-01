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

The library utilises Redis' `BLMOVE` command for inter-process communication and persisting the desired
state. So you'll need a Redis server. I also decided that legacy projects are unlikely to adopt a new
library like this and made Ruby >=3.0 a prerequisite.


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

Redis configuration will be taken from `REDIS_URL` or can be specified in a configuration block.

```ruby
ActiveActivity.configure do |config|
  config.redis_url = 'redis://127.0.0.1:6379/5'
end
```

### Writing activities

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


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/milgner/active_activity.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
