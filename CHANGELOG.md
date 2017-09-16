# Changelog

The following are lists of the notable changes included with each release.
This is intended to help keep people informed about notable changes between
versions, as well as provide a rough history. Each item is prefixed with
one of the following labels: `Added`, `Changed`, `Deprecated`,
`Removed`, `Fixed`, `Security`. We also use [Semantic Versioning](http://semver.org)
to manage the versions of this gem so
that you can set version constraints properly.

#### [Unreleased](https://github.com/exAspArk/batch-loader/compare/v1.0.2...HEAD)

* WIP

#### [v1.0.2](https://github.com/exAspArk/batch-loader/compare/v1.0.1...v1.0.2) – 2017-09-14

* `Added`: `BatchLoader#inspect` method because of Pry, which [swallows errors](https://github.com/pry/pry/issues/1642).

```ruby
# Before:
require 'pry'
binding.pry

pry(main)> result = BatchLoader.for(1).batch { |ids, loader| raise "Oops" };
pry(main)> result # Pry called result.inspect and swallowed the "Oops" error
# => #<BatchLoader:0x8>
pry(main)> result.id
# => NoMethodError: undefined method `id' for nil:NilClass
```

```ruby
# After:
require 'pry'
binding.pry

pry(main)> result = BatchLoader.for(1).batch { |ids, loader| raise "Oops" };
pry(main)> result
# => #<BatchLoader:0x140653946335160>
pry(main)> result.id
# => RuntimeError: Oops
```

* `Added`: benchmarks.
* `Fixed`: caching `nil`s for not loaded values only after successful `#batch` execution.
* `Changed`: internal implementation with Ruby `Forwardable`, don't delegate methods like `object_id` and `__send__`.

#### [v1.0.1](https://github.com/exAspArk/batch-loader/compare/v1.0.0...v1.0.1) – 2017-09-03

* `Fixed`: loading `BatchLoader` by requiring `Set`.

#### [v1.0.0](https://github.com/exAspArk/batch-loader/compare/v0.3.0...v1.0.0) – 2017-08-21

* `Removed`: `BatchLoader.sync!` and `BatchLoader#sync`. Now syncing is done implicitly when you call any method on the lazy object.

```ruby
def load_user(user_id)
  BatchLoader.for(user_id).batch { ... }
end

# Before:
users = [load_user(1), load_user(2), load_user(3)]
puts BatchLoader.sync!(users) # or users.map!(&:sync)
```

```ruby
# After:
users = [load_user(1), load_user(2), load_user(3)]
puts users
```

* `Removed`: `BatchLoader#load`. Use `loader` lambda instead:

```ruby
# Before:
BatchLoader.for(user_id).batch do |user_ids, batch_loader|
  user_ids.each { |user_id| batch_loader.load(user_id, user_id) }
end
```

```ruby
# After:
BatchLoader.for(user_id).batch do |user_ids, loader|
  user_ids.each { |user_id| loader.call(user_id, user_id) }
end
```

* `Changed`: use `BatchLoader::GraphQL` in GraphQL schema:

```ruby
# Before:
Schema = GraphQL::Schema.define do
  # ...
  lazy_resolve BatchLoader, :sync
end
```

```ruby
# After:
Schema = GraphQL::Schema.define do
  # ...
  use BatchLoader::GraphQL
end
```

#### [v0.3.0](https://github.com/exAspArk/batch-loader/compare/v0.2.0...v0.3.0) – 2017-08-03

* `Added`: `BatchLoader::Executor.clear_current` to clear cache manually.
* `Added`: tests and description how to use with GraphQL.

#### [v0.2.0](https://github.com/exAspArk/batch-loader/compare/v0.1.0...v0.2.0) – 2017-08-02

* `Added`: `cache: false` option to disable caching for resolved values.
* `Added`: `BatchLoader::Middleware` to clear cache between Rack requests.
* `Added`: more docs and tests.

#### [v0.1.0](https://github.com/exAspArk/batch-loader/compare/ed32edb...v0.1.0) – 2017-07-31

* `Added`: initial functional version.
