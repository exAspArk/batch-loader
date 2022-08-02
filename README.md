# BatchLoader

[![Build Status](https://travis-ci.org/exAspArk/batch-loader.svg?branch=master)](https://travis-ci.org/exAspArk/batch-loader)
[![Coverage Status](https://coveralls.io/repos/github/exAspArk/batch-loader/badge.svg)](https://coveralls.io/github/exAspArk/batch-loader)
[![Code Climate](https://img.shields.io/codeclimate/maintainability/exAspArk/batch-loader.svg)](https://codeclimate.com/github/exAspArk/batch-loader/maintainability)
[![Downloads](https://img.shields.io/gem/dt/batch-loader.svg)](https://rubygems.org/gems/batch-loader)
[![Latest Version](https://img.shields.io/gem/v/batch-loader.svg)](https://rubygems.org/gems/batch-loader)

This gem provides a generic lazy batching mechanism to avoid N+1 DB queries, HTTP queries, etc.

Developers from these companies use `BatchLoader`:

<a href="https://about.gitlab.com/"><img src="images/gitlab.png" height="35" width="114" alt="GitLab" style="max-width:100%;"></a>
<img src="images/space.png" height="35" width="10" alt="" style="max-width:100%;">
<a href="https://www.netflix.com/"><img src="images/netflix.png" height="35" width="110" alt="Netflix" style="max-width:100%;"></a>
<img src="images/space.png" height="35" width="10" alt="" style="max-width:100%;">
<a href="https://www.alibaba.com/"><img src="images/alibaba.png" height="35" width="86" alt="Alibaba" style="max-width:100%;"></a>
<img src="images/space.png" height="35" width="10" alt="" style="max-width:100%;">
<a href="https://www.universe.com/"><img src="images/universe.png" height="35" width="137" alt="Universe" style="max-width:100%;"></a>
<img src="images/space.png" height="35" width="10" alt="" style="max-width:100%;">
<a href="https://www.wealthsimple.com/"><img src="images/wealthsimple.png" height="35" width="150" alt="Wealthsimple" style="max-width:100%;"></a>
<img src="images/space.png" height="35" width="10" alt="" style="max-width:100%;">
<a href="https://decidim.org/"><img src="images/decidim.png" height="35" width="94" alt="Decidim" style="max-width:100%;"></a>

## Contents

* [Highlights](#highlights)
* [Usage](#usage)
  * [Why?](#why)
  * [Basic example](#basic-example)
  * [How it works](#how-it-works)
  * [RESTful API example](#restful-api-example)
  * [GraphQL example](#graphql-example)
  * [Loading multiple items](#loading-multiple-items)
  * [Batch key](#batch-key)
  * [Caching](#caching)
  * [Replacing methods](#replacing-methods)
* [Installation](#installation)
* [API](#api)
* [Related tools](#related-tools)
* [Implementation details](#implementation-details)
* [Development](#development)
* [Contributing](#contributing)
* [Alternatives](#alternatives)
* [License](#license)
* [Code of Conduct](#code-of-conduct)

## Highlights

* Generic utility to avoid N+1 DB queries, HTTP requests, etc.
* Adapted Ruby implementation of battle-tested tools like [Haskell Haxl](https://github.com/facebook/Haxl), [JS DataLoader](https://github.com/facebook/dataloader), etc.
* Batching is isolated and lazy, load data in batch where and when it's needed.
* Automatically caches previous queries (identity map).
* Thread-safe (`loader`).
* No need to share batching through variables or custom defined classes.
* No dependencies, no monkey-patches, no extra primitives such as Promises.

## Usage

### Why?

Let's have a look at the code with N+1 queries:

```ruby
def load_posts(ids)
  Post.where(id: ids)
end

posts = load_posts([1, 2, 3])  #      Posts      SELECT * FROM posts WHERE id IN (1, 2, 3)
                               #      _ ↓ _
                               #    ↙   ↓   ↘
users = posts.map do |post|    #   U    ↓    ↓   SELECT * FROM users WHERE id = 1
  post.user                    #   ↓    U    ↓   SELECT * FROM users WHERE id = 2
end                            #   ↓    ↓    U   SELECT * FROM users WHERE id = 3
                               #    ↘   ↓   ↙
                               #      ¯ ↓ ¯
puts users                     #      Users
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

posts = load_posts([1, 2, 3])  #      Posts      SELECT * FROM posts WHERE id IN (1, 2, 3)
                               #      _ ↓ _      SELECT * FROM users WHERE id IN (1, 2, 3)
                               #    ↙   ↓   ↘
users = posts.map do |post|    #   U    ↓    ↓
  post.user                    #   ↓    U    ↓
end                            #   ↓    ↓    U
                               #    ↘   ↓   ↙
                               #      ¯ ↓ ¯
puts users                     #      Users
```

But the problem here is that `load_posts` now depends on the child association and knows that it has to preload data for future use. And it'll do it every time, even if it's not necessary. Can we do better? Sure!

### Basic example

With `BatchLoader` we can rewrite the code above:

```ruby
def load_posts(ids)
  Post.where(id: ids)
end

def load_user(post)
  BatchLoader.for(post.user_id).batch do |user_ids, loader|
    User.where(id: user_ids).each { |user| loader.call(user.id, user) }
  end
end

posts = load_posts([1, 2, 3])  #      Posts      SELECT * FROM posts WHERE id IN (1, 2, 3)
                               #      _ ↓ _
                               #    ↙   ↓   ↘
users = posts.map do |post|    #   BL   ↓    ↓
  load_user(post)              #   ↓    BL   ↓
end                            #   ↓    ↓    BL
                               #    ↘   ↓   ↙
                               #      ¯ ↓ ¯
puts users                     #      Users      SELECT * FROM users WHERE id IN (1, 2, 3)
```

As we can see, batching is isolated and described right in a place where it's needed.

### How it works

In general, `BatchLoader` returns a lazy object. Each lazy object knows which data it needs to load and how to batch the query. As soon as you need to use the lazy objects, they will be automatically loaded once without N+1 queries.

So, when we call `BatchLoader.for` we pass an item (`user_id`) which should be collected and used for batching later. For the `batch` method, we pass a block which will use all the collected items (`user_ids`):

<pre>
BatchLoader.for(post.<b>user_id</b>).batch do |<b>user_ids</b>, loader|
  ...
end
</pre>

Inside the block we execute a batch query for our items (`User.where`). After that, all we have to do is to call `loader` by passing an item which was used in `BatchLoader.for` method (`user_id`) and the loaded object itself (`user`):

<pre>
BatchLoader.for(post.<b>user_id</b>).batch do |user_ids, loader|
  User.where(id: user_ids).each { |user| loader.call(<b>user.id</b>, <b>user</b>) }
end
</pre>

When we call any method on the lazy object, it'll be automatically loaded through batching for all instantiated `BatchLoader`s:

<pre>
puts users # => SELECT * FROM users WHERE id IN (1, 2, 3)
</pre>

For more information, see the [Implementation details](#implementation-details) section.

### RESTful API example

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
    BatchLoader.for(post).batch do |posts, loader|
      Parallel.each(posts, in_threads: 10) { |post| loader.call(post, post.rating) }
    end
  end

  # ...
end
```

`loader` is thread-safe. So, if `HttpClient` is also thread-safe, then with `parallel` gem we can execute all HTTP requests concurrently in threads (there are some benchmarks for [concurrent HTTP requests](https://github.com/exAspArk/concurrent_http_requests) in Ruby). Thanks to Matz, MRI releases GIL when thread hits blocking I/O – HTTP request in our case.

In the controller, all we have to do is to replace `post.rating` with the lazy `post.rating_lazy`:

```ruby
class PostsController < ApplicationController
  def index
    posts = Post.limit(10)
    serialized_posts = posts.map { |post| {id: post.id, rating: post.rating_lazy} }

    render json: serialized_posts
  end
end
```

`BatchLoader` caches the loaded values. To ensure that the cache is purged between requests in the app add the following middleware to your `config/application.rb`:

```ruby
config.middleware.use BatchLoader::Middleware
```

See the [Caching](#caching) section for more information.

### GraphQL example

Batching is particularly useful with GraphQL. Using such techniques as preloading data in advance to avoid N+1 queries can be very complicated, since a user can ask for any available fields in a query.

Let's take a look at the simple [graphql-ruby](https://github.com/rmosolgo/graphql-ruby) schema example:

```ruby
class MyProjectSchema < GraphQL::Schema
  query Types::QueryType
end

module Types
  class QueryType < Types::BaseObject
    field :posts, [PostType], null: false

    def posts
      Post.all
    end
  end
end

module Types
  class PostType < Types::BaseObject
    name "Post"

    field :user, UserType, null: false

    def user
      object.user # N+1 queries
    end
  end
end

module Types
  class UserType < Types::BaseObject
    name "User"

    field :name, String, null: false
  end
end
```

If we want to execute a simple query like the following, we will get N+1 queries for each `post.user`:

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
MyProjectSchema.execute(query)
```

To avoid this problem, all we have to do is to change the resolver to return `BatchLoader::GraphQL` ([#32](https://github.com/exAspArk/batch-loader/pull/32) explains why not just `BatchLoader`):

```ruby
module Types
  class PostType < Types::BaseObject
    name "Post"

    field :user, UserType, null: false

    def user
      BatchLoader::GraphQL.for(object.user_id).batch do |user_ids, loader|
        User.where(id: user_ids).each { |user| loader.call(user.id, user) }
      end
    end
  end
end
```

And setup GraphQL to use the built-in `lazy_resolve` method:

```ruby
class MyProjectSchema < GraphQL::Schema
  query Types::QueryType
  use BatchLoader::GraphQL
end
```

---

If you need to use BatchLoader with ActiveRecord in multiple places, you can use this `preload:` helper shared by [Aha!](https://www.aha.io/engineering/articles/automatically-avoiding-graphql-n-1s):

```rb
field :user, UserType, null: false, preload: :user
#                                   ^^^^^^^^^^^^^^
# Simply add this instead of defining custom `user` method with BatchLoader
```

And add this custom field resolver that uses ActiveRecord's preload functionality with BatchLoader:

```rb
# app/graphql/types/base_object.rb
field_class Types::PreloadableField

# app/graphql/types/preloadable_field.rb
class Types::PreloadableField < Types::BaseField
  def initialize(*args, preload: nil, **kwargs, &block)
    @preloads = preload
    super(*args, **kwargs, &block)
  end

  def resolve(type, args, ctx)
    return super unless @preloads

    BatchLoader::GraphQL.for(type).batch(key: self) do |records, loader|
      ActiveRecord::Associations::Preloader.new.preload(records.map(&:object), @preloads)
      records.each { |r| loader.call(r, super(r, args, ctx)) }
    end
  end
end
```

### Loading multiple items

For batches where there is no item in response to a call, we normally return `nil`. However, you can use `:default_value` to return something else instead:

```ruby
BatchLoader.for(post.user_id).batch(default_value: NullUser.new) do |user_ids, loader|
  User.where(id: user_ids).each { |user| loader.call(user.id, user) }
end
```

For batches where the value is some kind of collection, such as an Array or Hash, `loader` also supports being called with a block, which yields the _current_ value, and returns the _next_ value. This is extremely useful for 1:Many (`has_many`) relationships:

```ruby
BatchLoader.for(user.id).batch(default_value: []) do |user_ids, loader|
  Comment.where(user_id: user_ids).each do |comment|
    loader.call(comment.user_id) { |memo| memo << comment }
  end
end
```

### Batch key

It's possible to reuse the same `BatchLoader#batch` block for loading different types of data by specifying a unique `key`.
For example, with polymorphic associations:

```ruby
def lazy_association(post)
  id = post.association_id
  key = post.association_type

  BatchLoader.for(id).batch(key: key) do |ids, loader, args|
    model = Object.const_get(args[:key])
    model.where(id: ids).each { |record| loader.call(record.id, record) }
  end
end
post1 = Post.save(association_id: 1, association_type: 'Tag')
post2 = Post.save(association_id: 1, association_type: 'Category')

lazy_association(post1) # SELECT * FROM tags WHERE id IN (1)
lazy_association(post2) # SELECT * FROM categories WHERE id IN (1)
```

It's also required to pass custom `key` when using `BatchLoader` with metaprogramming (e.g. `eval`).

### Caching

By default `BatchLoader` caches the loaded values. You can test it by running something like:

```ruby
def user_lazy(id)
  BatchLoader.for(id).batch do |ids, loader|
    User.where(id: ids).each { |user| loader.call(user.id, user) }
  end
end

puts user_lazy(1) # SELECT * FROM users WHERE id IN (1)
# => <#User:...>

puts user_lazy(1) # no request
# => <#User:...>
```

Usually, it's just enough to clear the cache between HTTP requests in the app. To do so, simply add the middleware:

```ruby
use BatchLoader::Middleware
```

To drop the cache manually you can run:

```ruby
puts user_lazy(1) # SELECT * FROM users WHERE id IN (1)
puts user_lazy(1) # no request

BatchLoader::Executor.clear_current

puts user_lazy(1) # SELECT * FROM users WHERE id IN (1)
```

In some rare cases it's useful to disable caching for `BatchLoader`. For example, in tests or after data mutations:

```ruby
def user_lazy(id)
  BatchLoader.for(id).batch(cache: false) do |ids, loader|
    # ...
  end
end

puts user_lazy(1) # SELECT * FROM users WHERE id IN (1)
puts user_lazy(1) # SELECT * FROM users WHERE id IN (1)
```

If you set `cache: false`, it's likely you also want `replace_methods: false` (see below section).

### Replacing methods

By default, `BatchLoader` replaces methods on its instance by calling `#define_method` after batching to copy methods from the loaded value.
This consumes some time but allows to speed up any future method calls on the instance.
In some cases, when there are a lot of instances with a huge number of defined methods, this initial process of replacing the methods can be slow.
You may consider avoiding the "up front payment" and "pay as you go" with `#method_missing` by disabling the method replacement:

```ruby
BatchLoader.for(id).batch(replace_methods: false) do |ids, loader|
  # ...
end
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

## API

```ruby
BatchLoader.for(item).batch(
  default_value: default_value,
  cache: cache,
  replace_methods: replace_methods,
  key: key
) do |items, loader, args|
  # ...
end
```

| Argument Key      | Default                                                              | Description                                                                           |
| ---------------   | ---------------------------------------------                        | -------------------------------------------------------------                         |
| `item`            | -                                                                    | Item which will be collected and used for batching.                                   |
| `default_value`   | `nil`                                                                | Value returned by default after batching.                                             |
| `cache`           | `true`                                                               | Set `false` to disable caching between the same executions.                           |
| `replace_methods` | `true`                                                               | Set `false` to use `#method_missing` instead of replacing the methods after batching. |
| `key`             | `nil`                                                                | Pass custom key to uniquely identify the batch block.                                 |
| `items`           | -                                                                    | List of collected items for batching.                                                 |
| `loader`          | -                                                                    | Lambda which should be called to load values loaded in batch.                         |
| `args`            | `{default_value: nil, cache: true, replace_methods: true, key: nil}` | Arguments passed to the `batch` method.                                               |

## Related tools

These gems are built by using `BatchLoader`:

* [decidim-core](https://github.com/decidim/decidim/) – participatory democracy framework made with Ruby on Rails.
* [ams_lazy_relationships](https://github.com/Bajena/ams_lazy_relationships/) – ActiveModel Serializers add-on for eliminating N+1 queries.
* [batch-loader-active-record](https://github.com/mathieul/batch-loader-active-record/) – ActiveRecord lazy association generator to avoid N+1 DB queries.

`BatchLoader` in other programming languages:

* [batch_loader](https://github.com/exaspark/batch_loader) - Elixir implementation.

## Implementation details

See the [slides](https://speakerdeck.com/exaspark/batching-a-powerful-way-to-solve-n-plus-1-queries) [37-42].

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/exAspArk/batch-loader. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## Alternatives

There are some other Ruby implementations for batching such as:

* [shopify/graphql-batch](https://github.com/shopify/graphql-batch)
* [sheerun/dataloader](https://github.com/sheerun/dataloader)

However, `batch-loader` has some differences:

* It is implemented for general usage and can be used not only with GraphQL. In fact, we use it for RESTful APIs and GraphQL on production at the same time.
* It doesn't try to mimic implementations in other programming languages which have an asynchronous nature. So, it doesn't load extra dependencies to bring such primitives as Promises, which are not very popular in Ruby community.
Instead, it uses the idea of lazy objects, which are included in the [Ruby standard library](https://ruby-doc.org/core-2.4.1/Enumerable.html#method-i-lazy). These lazy objects allow one to return the necessary data at the end when it's necessary.
* It doesn't force you to share batching through variables or custom defined classes, just pass a block to the `batch` method.
* It doesn't require to return an array of the loaded objects in the same order as the passed items. I find it difficult to satisfy these constraints: to sort the loaded objects and add `nil` values for the missing ones. Instead, it provides the `loader` lambda which simply maps an item to the loaded object.
* It doesn't depend on any other external dependencies. For example, no need to load huge external libraries for thread-safety, the gem is thread-safe out of the box.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Batch::Loader project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/exAspArk/batch-loader/blob/master/CODE_OF_CONDUCT.md).
