require "batch_loader/version"
require "batch_loader/executor"

class BatchLoader
  def self.for(item)
    new(item: item)
  end

  def self.sync!(value)
    case value
    when Array
      value.map { |v| sync!(v) }
    when Hash
      value.each { |k, v| value[k] = sync!(v) }
    when BatchLoader
      sync!(value.sync)
    else
      value
    end
  end

  def initialize(item:)
    @item = item
  end

  def batch(&batch_block)
    @batch_block = batch_block
    executor.add_item(@item, &@batch_block)
    self
  end

  def load(item, loaded_item)
    executor.save(item, loaded_item, &@batch_block)
  end

  def sync
    unless executor.saved?(&@batch_block)
      items = executor.items(&@batch_block)
      @batch_block.call(items, self)
    end

    executor.find(@item, &@batch_block)
  end

  private

  def executor
    BatchLoader::Executor.ensure_current
  end
end
