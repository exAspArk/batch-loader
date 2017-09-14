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
  x.report("with BatchLoader with cache") { batch_loader_with_cache.id }
  x.report("with BatchLoader without cache") { batch_loader_without_cache.id }
  x.compare!
end

# Warming up --------------------------------------
# without BatchLoader            1.000  i/100ms
# with BatchLoader with cache    1.000  i/100ms
# with BatchLoader without cache 1.000  i/100ms

# Calculating -------------------------------------
# without BatchLoader            939.708k (±19.2%) i/s - 3.241M   in 3.907448s
# with BatchLoader with cache    990.611k (± 8.3%) i/s - 3.283M
# with BatchLoader without cache 76.292k (±18.0%) i/s  - 350.402k in 4.886185s

# Comparison:
# with BatchLoader with cache:    990611.0 i/s
# without BatchLoader:            939708.2 i/s - same-ish: difference falls within error
# with BatchLoader without cache: 76292.0 i/s  - 12.98x  slower
