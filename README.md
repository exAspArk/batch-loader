# BatchLoader

[![Build Status](https://travis-ci.org/exAspArk/batch-loader.svg?branch=master)](https://travis-ci.org/exAspArk/batch-loader)
[![Coverage Status](https://coveralls.io/repos/github/exAspArk/batch-loader/badge.svg)](https://coveralls.io/github/exAspArk/batch-loader)
[![Code Climate](https://img.shields.io/codeclimate/github/exAspArk/batch-loader.svg)](https://codeclimate.com/github/exAspArk/batch-loader)
[![Downloads](https://img.shields.io/gem/dt/batch-loader.svg)](https://rubygems.org/gems/batch-loader)
[![Latest Version](https://img.shields.io/gem/v/batch-loader.svg)](https://rubygems.org/gems/batch-loader)

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

But the problem here is that `load_posts` now depends on the child association and knows that it has to preload the data for `load_users`. And it'll do it every time, even if it's not necessary. Can we do better? Sure!

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

In general, `BatchLoader` returns a lazy object. In other programming languages it usually called Promise, but I personally prefer to call it lazy, since Ruby already uses the name in standard library :) Each lazy object knows which data it needs to load and how to batch the query. When all the lazy objects are collected it's possible to resolve them once without N+1 queries.

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
    serialized_posts = posts.map { |post| {id: post.id, rating: post.rating} } # N+1 HTTP requests for each post.rating

    render json: serialized_posts
  end
end
```

As we can see, the code above will make N+1 HTTP requests, one for each post. Let's batch the requests with a gem called [parallel](https://github.com/grosser/parallel):

```ruby
class Post < ApplicationRecord
  def rating_lazy
    BatchLoader.for(post).batch do |posts, batch_loader|
      Parallel.each(posts, in_threads: 10) { |post| batch_loader.load(post, post.rating) }
    end
  end

  # ...
end
```

`BatchLoader#load` is thread-safe. So, if `HttpClient` is also thread-safe, then with `parallel` gem we can execute all HTTP requests concurrently in threads (there are some benchmarks for [concurrent HTTP requests](https://github.com/exAspArk/concurrent_http_requests) in Ruby). Thanks to Matz, MRI releases GIL when thread hits blocking I/O – HTTP request in our case.

Now we can resolve all `BatchLoader` objects in the controller:

```ruby
class PostsController < ApplicationController
  def index
    posts = Post.limit(10)
    serialized_posts = posts.map { |post| {id: post.id, rating: post.rating_lazy} }
    render json: BatchLoader.sync!(serialized_posts)
  end
end
```

`BatchLoader` caches the resolved values. To ensure that the cache is purged between requests in the app add the following middleware to your `config/application.rb`:

```ruby
config.middleware.use BatchLoader::Middleware
```

See the [Caching](#caching) section for more information.

### GraphQL example

With GraphQL using batching is particularly useful. You can't use usual techniques such as preloading associations in advance to avoid N+1 queries.
Since you don't know which fields user is going to ask in a query.

Let's take a look at the simple [graphql-ruby](https://github.com/rmosolgo/graphql-ruby) schema example:

```ruby
Schema = GraphQL::Schema.define do
  query QueryType
end

QueryType = GraphQL::ObjectType.define do
  name "Query"
  field :posts, !types[PostType], resolve: ->(obj, args, ctx) { Post.all }
end

PostType = GraphQL::ObjectType.define do
  name "Post"
  field :user, !UserType, resolve: ->(post, args, ctx) { post.user } # N+1 queries
end

UserType = GraphQL::ObjectType.define do
  name "User"
  field :name, !types.String
end
```

If we want to execute a simple query like:

```ruby
query = "
{
  posts {
    user {
      name
    }
  }
}
"
Schema.execute(query, variables: {}, context: {})
```

We will get N+1 queries for each `post.user`. To avoid this problem, all we have to do is to change the resolver to use `BatchLoader`:

```ruby
PostType = GraphQL::ObjectType.define do
  name "Post"
  field :user, !UserType, resolve: ->(post, args, ctx) do
    BatchLoader.for(post.user_id).batch do |user_ids, batch_loader|
      User.where(id: user_ids).each { |user| batch_loader.load(user.id, user) }
    end
  end
end
```

And setup GraphQL with built-in `lazy_resolve` method:

```ruby
Schema = GraphQL::Schema.define do
  query QueryType
  lazy_resolve BatchLoader, :sync
end
```

### Caching

By default `BatchLoader` caches the resolved values. You can test it by running something like:

```ruby
def user_lazy(id)
  BatchLoader.for(id).batch do |ids, batch_loader|
    User.where(id: ids).each { |user| batch_loader.load(user.id, user) }
  end
end

user_lazy(1)      # no request
# => <#BatchLoader>

user_lazy(1).sync # SELECT * FROM users WHERE id IN (1)
# => <#User>

user_lazy(1).sync # no request
# => <#User>
```

To drop the cache manually you can run:

```ruby
user_lazy(1).sync # SELECT * FROM users WHERE id IN (1)
user_lazy(1).sync # no request

BatchLoader::Executor.clear_current

user_lazy(1).sync # SELECT * FROM users WHERE id IN (1)
```

Usually, it's just enough to clear the cache between HTTP requests in the app. To do so, simply add the middleware:

```ruby
# calls "BatchLoader::Executor.clear_current" after each request
use BatchLoader::Middleware
```

In some rare cases it's useful to disable caching for `BatchLoader`. For example, in tests or after data mutations:

```ruby
def user_lazy(id)
  BatchLoader.for(id).batch(cache: false) do |ids, batch_loader|
    # ...
  end
end

user_lazy(1).sync # SELECT * FROM users WHERE id IN (1)
user_lazy(1).sync # SELECT * FROM users WHERE id IN (1)
```

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

Coming soon

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/exAspArk/batch-loader. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Batch::Loader project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/exAspArk/batch-loader/blob/master/CODE_OF_CONDUCT.md).
