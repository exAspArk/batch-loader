# frozen_string_literal: true

require_relative "./executor"

class BatchLoader
  class ExecutorProxy
    attr_reader :default_value, :block, :global_executor

    def initialize(default_value, key, &block)
      @default_value = default_value
      @block = block
      @block_hash_key = key || block.source_location
      @global_executor = BatchLoader::Executor.ensure_current
    end

    def add(item:, context:)
      context_to_load[item] = context
      items_to_load << item
    end

    def list_items
      items_to_load.to_a
    end

    def list_context
      context_to_load
    end

    def delete(items:)
      items.each { |value| global_executor.context_by_block[@block_hash_key].delete(value) }
      global_executor.items_by_block[@block_hash_key] = items_to_load - items
    end

    def load(item:, value:)
      loaded[item] = value
    end

    def loaded_value(item:)
      if value_loaded?(item: item)
        loaded[item]
      else
        @default_value.dup
      end
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

    def context_to_load
      global_executor.context_by_block[@block_hash_key]
    end

    def loaded
      global_executor.loaded_values_by_block[@block_hash_key]
    end
  end
end
