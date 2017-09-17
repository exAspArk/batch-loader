# frozen_string_literal: true

require_relative "./executor"

class BatchLoader
  class ExecutorProxy
    attr_reader :block, :global_executor

    def initialize(&block)
      @block = block
      @block_hash_key = block.source_location
      @global_executor = BatchLoader::Executor.ensure_current
    end

    def add(item:)
      items_to_load << item
    end

    def list_items
      items_to_load.to_a
    end

    def delete(items:)
      global_executor.items_by_block[@block_hash_key] = items_to_load - items
    end

    def load(item:, value:)
      loaded[item] = value
    end

    def loaded_value(item:)
      loaded[item]
    end

    def value_loaded?(item:)
      loaded.key?(item)
    end

    def unload_value(item:)
      loaded.delete(item)
    end

    private

    def items_to_load
      global_executor.items_by_block[@block_hash_key]
    end

    def loaded
      global_executor.loaded_values_by_block[@block_hash_key]
    end
  end
end
