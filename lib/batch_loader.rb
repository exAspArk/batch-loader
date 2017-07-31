require "batch_loader/version"
require "batch_loader/executor_proxy"
require "batch_loader/middleware"

class BatchLoader
  NoBatchError = Class.new(StandardError)
  BatchAlreadyExistsError = Class.new(StandardError)

  class << self
    def for(item)
      new(item: item)
    end

    def sync!(value)
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
  end

  attr_reader :item, :batch_block, :cache

  def initialize(item:)
    @item = item
  end

  def batch(cache: true, &batch_block)
    raise BatchAlreadyExistsError if @batch_block
    @cache = cache
    @batch_block = batch_block
    executor_for_block.add(item: item)
    self
  end

  def load(item, value)
    executor_for_block.load(item: item, value: value)
  end

  def sync
    unless executor_for_block.value_loaded?(item: item)
      batch_block.call(executor_for_block.list_items, self)
      executor_for_block.delete_items
    end
    result = executor_for_block.loaded_value(item: item)
    purge_cache unless cache
    result
  end

  private

  def executor_for_block
    @executor_for_block ||= begin
      raise NoBatchError.new("Please provide a batch block first") unless batch_block
      BatchLoader::ExecutorProxy.new(&batch_block)
    end
  end

  def purge_cache
    executor_for_block.unload_value(item: item)
    executor_for_block.add(item: item)
  end
end
