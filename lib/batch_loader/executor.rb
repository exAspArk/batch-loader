class BatchLoader
  class Executor
    NAMESPACE = :batch_loader

    def self.ensure_current
      Thread.current[NAMESPACE] = Thread.current[NAMESPACE] || new
    end

    def self.clear_current
      Thread.current[NAMESPACE] = nil
    end

    def initialize
      @items_by_batch_block = Hash.new { |hash, key| hash[key] = [] }
      @loaded_items_by_batch_block = Hash.new { |hash, key| hash[key] = {} }
    end

    def add_item(item, &batch_block)
      @items_by_batch_block[batch_block.source_location] << item
    end

    def items(&batch_block)
      @items_by_batch_block[batch_block.source_location]
    end

    def save(item, loaded_item, &batch_block)
      @loaded_items_by_batch_block[batch_block.source_location][item] = loaded_item
    end

    def saved?(&batch_block)
      @loaded_items_by_batch_block.key?(batch_block.source_location)
    end

    def find(item, &batch_block)
      @loaded_items_by_batch_block.dig(batch_block.source_location, item)
    end
  end
end
