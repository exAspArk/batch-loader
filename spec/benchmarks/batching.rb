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
#                 pure    957.329k (±16.7%) i/s -      3.256M in   3.849922s
#       already synced    987.154k (± 9.8%) i/s -      3.117M
#           with cache    290.951  (±16.8%) i/s -      1.399k in   4.999113s
#    with purged cache    285.393  (±17.5%) i/s -      1.370k in   5.001320s
#        without cache     80.347k (±18.5%) i/s -    363.375k in   4.882113s

# Comparison:
#       already synced:   987153.6 i/s
#                 pure:   957329.3 i/s - same-ish: difference falls within error
#        without cache:    80347.0 i/s - 12.29x  slower
#           with cache:      291.0 i/s - 3392.85x  slower
#    with purged cache:      285.4 i/s - 3458.92x  slower
