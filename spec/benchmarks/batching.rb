# frozen_string_literal: true

# Usage: ruby spec/benchmarks/batching.rb

require 'benchmark/ips'

require_relative "../../lib/batch_loader"
require_relative "../fixtures/models"

User.save(id: 1)

def batch_loader
  BatchLoader.for(1).batch do |ids, loader|
    User.where(id: ids).each { |user| loader.call(user.id, user) }
  end
end

batch_loader_with_cache = batch_loader

batch_loader_without_cache = BatchLoader.for(1).batch(cache: false) do |ids, loader|
  User.where(id: ids).each { |user| loader.call(user.id, user) }
end

Benchmark.ips do |x|
  x.config(time: 5, warmup: 0)
  x.report("pure") { User.where(id: [1]).first.id }
  x.report("already synced") { batch_loader_with_cache.id }
  x.report("with cache") { batch_loader.id }
  x.report("with purged cache") { batch_loader.id ; BatchLoader::Executor.clear_current }
  x.report("without cache") { batch_loader_without_cache.id }
  x.compare!
end

# Warming up --------------------------------------
#                 pure     1.000  i/100ms
#       already synced     1.000  i/100ms
#           with cache     1.000  i/100ms
#    with purged cache     1.000  i/100ms
#        without cache     1.000  i/100ms
# Calculating -------------------------------------
#                 pure    960.344k (±16.1%) i/s -      3.283M
#       already synced    989.078k (± 9.0%) i/s -      3.200M
#           with cache      8.400k (±20.1%) i/s -     39.442k in   4.982755s
#    with purged cache      7.218k (±19.0%) i/s -     34.015k in   4.981920s
#        without cache     76.683k (±19.5%) i/s -    345.987k in   4.874809s

# Comparison:
#       already synced:   989077.6 i/s
#                 pure:   960343.8 i/s - same-ish: difference falls within error
#        without cache:    76682.6 i/s - 12.90x  slower
#           with cache:     8399.6 i/s - 117.75x  slower
#    with purged cache:     7218.5 i/s - 137.02x  slower
