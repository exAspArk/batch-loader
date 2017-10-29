# frozen_string_literal: true

require_relative "./executor"

class BatchLoader
  class ExecutorProxy
    attr_reader :default_value, :block, :global_executor

    def initialize(default_value, &block)
      @default_value = default_value
      @value_appendable = @default_value.respond_to?(:push)
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
      loaded[item] = if value_appendable?
          loaded_value(item: item).push(value)
        else
          value
        end
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

    def value_appendable?
      @value_appendable
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
