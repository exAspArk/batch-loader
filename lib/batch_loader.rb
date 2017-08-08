require "batch_loader/version"
require "batch_loader/executor_proxy"
require "batch_loader/middleware"

class BatchLoader
  NoBatchError = Class.new(StandardError)
  BatchAlreadyExistsError = Class.new(StandardError)

  def self.for(item)
    new(item: item)
  end

  def self.sync!(value)
    case value
    when Array
      value.map! { |v| sync!(v) }
    when Hash
      value.each { |k, v| value[k] = sync!(v) }
    when BatchLoader
      sync!(value.sync)
    else
      value
    end
  end

  attr_reader :item, :batch_block, :cache

  def initialize(item:)
    @item = item
  end

  def batch(cache: true, &batch_block)
    raise BatchAlreadyExistsError if @batch_block
    @cache = cache
    @batch_block = batch_block
    executor_proxy.add(item: item)
    self
  end

  def load(item, value)
    executor_proxy.load(item: item, value: value)
  end

  def sync
    unless executor_proxy.value_loaded?(item: item)
      batch_block.call(executor_proxy.list_items, self)
      executor_proxy.delete_items
    end
    result = executor_proxy.loaded_value(item: item)
    purge_cache unless cache
    result
  end

  private

  def executor_proxy
    @executor_proxy ||= begin
      raise NoBatchError.new("Please provide a batch block first") unless batch_block
      BatchLoader::ExecutorProxy.new(&batch_block)
    end
  end

  def purge_cache
    executor_proxy.unload_value(item: item)
    executor_proxy.add(item: item)
  end
end

