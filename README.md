# BatchLoader

[![Build Status](https://travis-ci.org/exAspArk/batch-loader.svg?branch=master)](https://travis-ci.org/exAspArk/batch-loader)

Simple tool to avoid N+1 DB queries, HTTP requests, etc.

## Contents

* [Highlights](#highlights)
* [Usage](#usage)
  * [Why?](#why)
  * [Basic example](#basic-example)
  * [How it works](#how-it-works)
  * [REST API example](#rest-api-example)
  * [GraphQL example](#graphql-example)
  * [Caching](#caching)
* [Installation](#installation)
* [Implementation details](#implementation-details)
* [Testing](#testing)
* [Development](#development)
* [Contributing](#contributing)
* [License](#license)
* [Code of Conduct](#code-of-conduct)

## Highlights

* Generic utility to avoid N+1 DB queries, HTTP requests, etc.
* Adapted Ruby implementation of battle-tested tools like [Haskell Haxl](https://github.com/facebook/Haxl), [JS DataLoader](https://github.com/facebook/dataloader), etc.
* Parent objects don't have to know about children's requirements, batching is isolated.
* Automatically caches previous queries.
* Doesn't require to create custom classes.
* Thread-safe (`BatchLoader#load`).
* Has zero dependencies.
* Works with any Ruby code, including REST APIs and GraphQL.

## Usage

### Why?

Let's have a look at the code with N+1 queries:

```ruby
def load_posts(ids)
  Post.where(id: ids)
end

def load_users(posts)
  posts.map { |post| post.user }
end

posts = load_posts([1, 2, 3])  #      Posts      SELECT * FROM posts WHERE id IN (1, 2, 3)
                               #      _ ↓ _
                               #    ↙   ↓   ↘
                               #   U    ↓    ↓   SELECT * FROM users WHERE id = 1
users = load_users(post)       #   ↓    U    ↓   SELECT * FROM users WHERE id = 2
                               #   ↓    ↓    U   SELECT * FROM users WHERE id = 3
                               #    ↘   ↓   ↙
                               #      ¯ ↓ ¯
users.map { |u| user.name }    #      Users
```

The naive approach would be to preload dependent objects on the top level:

```ruby
# With ORM in basic cases
def load_posts(ids)
  Post.where(id: ids).includes(:user)
end

# But without ORM or in more complicated cases you will have to do something like:
def load_posts(ids)
  # load posts
  posts = Post.where(id: ids)
  user_ids = posts.map(&:user_id)

  # load users
  users = User.where(id: user_ids)
  user_by_id = users.each_with_object({}) { |user, memo| memo[user.id] = user }

  # map user to post
  posts.each { |post| post.user = user_by_id[post.user_id] }
end

def load_users(posts)
  posts.map { |post| post.user }
end

posts = load_posts([1, 2, 3])  #      Posts      SELECT * FROM posts WHERE id IN (1, 2, 3)
                               #      _ ↓ _      SELECT * FROM users WHERE id IN (1, 2, 3)
                               #    ↙   ↓   ↘
                               #   U    ↓    ↓
users = load_posts(post.user)  #   ↓    U    ↓
                               #   ↓    ↓    U
                               #    ↘   ↓   ↙
                               #      ¯ ↓ ¯
users.map { |u| user.name }    #      Users
```

But the problem here is that `load_posts` now depends on the child association. Plus it'll preload the association every time, even if it's not necessary. Can we do better? Sure!

### Basic example

With `BatchLoader` we can rewrite the code above:

```ruby
def load_posts(ids)
  Post.where(id: ids)
end

def load_users(posts)
  posts.map do |post|
    BatchLoader.for(post.user_id).batch do |user_ids, batch_loader|
      User.where(id: user_ids).each { |u| batch_loader.load(u.id, user) }
    end
  end
end

posts = load_posts([1, 2, 3])         #      Posts      SELECT * FROM posts WHERE id IN (1, 2, 3)
                                      #      _ ↓ _
                                      #    ↙   ↓   ↘
                                      #   BL   ↓    ↓
users = load_users(posts)             #   ↓    BL   ↓
                                      #   ↓    ↓    BL
                                      #    ↘   ↓   ↙
                                      #      ¯ ↓ ¯
BatchLoader.sync!(users).map(&:name)  #      Users      SELECT * FROM users WHERE id IN (1, 2, 3)
```

As we can see, batching is isolated and described right in a place where it's needed.

### How it works

In general, `BatchLoader` returns an object which in other similar implementations is call Promise. Each Promise knows which data it needs to load and how to batch the query. When all the Promises are collected it's possible to resolve them once without N+1 queries.

So, when we call `BatchLoader.for` we pass an item (`user_id`) which should be batched. For the `batch` method, we pass a block which uses all the collected items (`user_ids`):

<pre>
BatchLoader.for(post.<b>user_id</b>).batch do |<b>user_ids</b>, batch_loader|
  ...
end
</pre>

Inside the block we execute a batch query for our items (`User.where`). After that, all we have to do is to call `load` method and pass an item which was used in `BatchLoader.for` method (`user_id`) and the loaded object itself (`user`):

<pre>
BatchLoader.for(post.<b>user_id</b>).batch do |user_ids, batch_loader|
  User.where(id: user_ids).each { |u| batch_loader.load(<b>u.id</b>, <b>user</b>) }
end
</pre>

Now we can resolve all the collected `BatchLoader` objects:

<pre>
BatchLoader.sync!(users) # => SELECT * FROM users WHERE id IN (1, 2, 3)
</pre>

For more information, see the [Implementation details](#implementation-details) section.

### REST API example

Now imagine we have a regular Rails app with N+1 HTTP requests:

```ruby
# app/models/post.rb
class Post < ApplicationRecord
  def rating
    HttpClient.request(:get, "https://example.com/ratings/#{id}")
  end
end

# app/controllers/posts_controller.rb
class PostsController < ApplicationController
  def index
    posts = Post.limit(10)
    serialized_posts = posts.map { |post| {id: post.id, rating: post.rating} }

    render json: serialized_posts
  end
end
```

As we can see, the code above will make N+1 HTTP requests, one for each post. Let's batch the requests with a gem called [parallel](https://github.com/grosser/parallel):

```ruby
# app/models/post.rb
class Post < ApplicationRecord
  def rating_lazy
    BatchLoader.for(post).batch do |posts, batch_loader|
      Parallel.each(posts, in_threads: 10) { |post| batch_loader.load(post, post.rating) }
    end
  end

  def rating
    HttpClient.request(:get, "https://example.com/ratings/#{id}")
  end
end
```

`BatchLoader#load` is thread-safe. So, if `HttpClient` is also thread-safe, then with `parallel` gem we can execute all HTTP requests concurrently in threads (there are some benchmarks for [concurrent HTTP requests](https://github.com/exAspArk/concurrent_http_requests) in Ruby). Thanks to Matz, MRI releases GIL when thread hits blocking I/O – HTTP request in our case.

Now we can resolve all `BatchLoader` objects in the controller:

```ruby
# app/controllers/posts_controller.rb
class PostsController < ApplicationController
  def index
    posts = Post.limit(10)
    serialized_posts = posts.map { |post| {id: post.id, rating: post.rating_lazy} }
    render json: BatchLoader.sync!(serialized_posts)
  end
end
```

`BatchLoader` caches the resolved values. To ensure that the cache is purged for each request in the app add the following middleware:

```ruby
# config/application.rb
config.middleware.use BatchLoader::Middleware
```

See the [Caching](#caching) section for more information.

### GraphQL example

TODO

### Caching

TODO

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'batch-loader'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install batch-loader

## Implementation details

TODO

## Testing

TODO

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/exAspArk/batch-loader. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Batch::Loader project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/exAspArk/batch-loader/blob/master/CODE_OF_CONDUCT.md).
