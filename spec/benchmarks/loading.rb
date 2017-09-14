# frozen_string_literal: true

# Usage: ruby spec/benchmarks/loading.rb

require 'benchmark/ips'
require "batch_loader"

require_relative "../fixtures/models"

User.save(id: 1)

batch_loader_with_cache = BatchLoader.for(1).batch do |ids, loader|
  User.where(id: ids).each { |user| loader.call(user.id, user) }
end

batch_loader_without_cache = BatchLoader.for(1).batch(cache: false) do |ids, loader|
  User.where(id: ids).each { |user| loader.call(user.id, user) }
end

Benchmark.ips do |x|
  x.config(time: 5, warmup: 0)
  x.report("without BatchLoader") { User.where(id: [1]).first.id }
  x.report("with cache") { batch_loader_with_cache.id }
  x.report("with purged cache") { batch_loader_with_cache.id ; BatchLoader::Executor.clear_current }
  x.report("without cache") { batch_loader_without_cache.id }
  x.compare!
end

# Warming up --------------------------------------
#  without BatchLoader     1.000  i/100ms
#           with cache     1.000  i/100ms
#    with purged cache     1.000  i/100ms
#        without cache     1.000  i/100ms
# Calculating -------------------------------------
#  without BatchLoader    972.844k (±13.5%) i/s -      3.458M
#           with cache    991.569k (± 7.7%) i/s -      3.281M
#    with purged cache    989.499k (± 8.1%) i/s -      3.570M
#        without cache     76.256k (±16.9%) i/s -    345.629k in   4.886612s

# Comparison:
#           with cache:   991569.5 i/s
#    with purged cache:   989499.4 i/s - same-ish: difference falls within error
#  without BatchLoader:   972844.4 i/s - same-ish: difference falls within error
#        without cache:    76256.3 i/s - 13.00x  slower
