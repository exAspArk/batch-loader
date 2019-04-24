# Usage: ruby spec/benchmarks/caching.rb

# no replacement + many methods _can_ be faster than replacement + many
# methods, but this depends on the values of METHOD_COUNT, OBJECT_COUNT,
# and CALL_COUNT, so tweak them for your own scenario!

require 'benchmark'
require_relative '../../lib/batch_loader'

METHOD_COUNT = 1000 # methods on the object with a large interface
OBJECT_COUNT = 1000 # objects in the batch
CALL_COUNT = 1000 # times a method is called on the loaded object

class ManyMethods
  1.upto(METHOD_COUNT) do |i|
    define_method("method_#{i}") { i }
  end
end

class FewMethods
  def method_1
    1
  end
end

def load_value(x, **opts)
  BatchLoader.for(x).batch(opts) do |xs, loader|
    xs.each { |x| loader.call(x, x) }
  end
end

def benchmark(klass:, **opts)
  OBJECT_COUNT.times do
    value = load_value(klass.new, opts)
    CALL_COUNT.times { value.method_1 }
  end
end

Benchmark.bmbm do |x|
  x.report('replacement + many methods') { benchmark(klass: ManyMethods) }
  x.report('replacement + few methods') { benchmark(klass: FewMethods) }
  x.report('no replacement + many methods') { benchmark(klass: ManyMethods, replace_methods: false) }
  x.report('no replacement + few methods') { benchmark(klass: FewMethods, replace_methods: false) }
  x.report('no cache + many methods') { benchmark(klass: ManyMethods, cache: false, replace_methods: false) }
  x.report('no cache + few methods') { benchmark(klass: FewMethods, cache: false, replace_methods: false) }
end

# Rehearsal -----------------------------------------------------------------
# replacement + many methods      2.260000   0.030000   2.290000 (  2.603038)
# replacement + few methods       0.450000   0.000000   0.450000 (  0.457151)
# no replacement + many methods   0.440000   0.010000   0.450000 (  0.454444)
# no replacement + few methods    0.370000   0.000000   0.370000 (  0.380699)
# no cache + many methods        31.780000   0.240000  32.020000 ( 33.552620)
# no cache + few methods         31.510000   0.200000  31.710000 ( 32.294752)
# ------------------------------------------------------- total: 67.290000sec

#                                     user     system      total        real
# replacement + many methods      2.330000   0.010000   2.340000 (  2.382599)
# replacement + few methods       0.430000   0.000000   0.430000 (  0.438584)
# no replacement + many methods   0.420000   0.000000   0.420000 (  0.434069)
# no replacement + few methods    0.440000   0.010000   0.450000 (  0.452091)
# no cache + many methods        31.630000   0.160000  31.790000 ( 32.337531)
# no cache + few methods         36.590000   0.370000  36.960000 ( 40.701712)
