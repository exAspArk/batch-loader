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
# without BatchLoader            965.088k (±15.1%) i/s - 3.399M   in 3.864552s
# with BatchLoader with cache    991.089k (± 8.0%) i/s - 3.272M
# with BatchLoader without cache 75.239k (±18.1%) i/s  - 345.350k in 4.883875s

# Comparison:
# with BatchLoader with cache:    991089.2 i/s
# without BatchLoader:            965088.1 i/s - same-ish: difference falls within error
# with BatchLoader without cache: 75238.7 i/s  - 13.17x slower
