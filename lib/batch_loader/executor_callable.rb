# frozen_string_literal: true

class BatchLoader
  class ExecutorCallable
    attr_reader :executor_proxy

    NULL_VALUE = :batch_loader_null

    def initialize(executor_proxy)
      @executor_proxy = executor_proxy
    end

    def call(item, value = NULL_VALUE)
      if block_given?
        raise ArgumentError, "Please pass a value or a block, not both" if value != NULL_VALUE
        next_value = yield executor_proxy.loaded_value(item: item)
      else
        raise ArgumentError, "Please pass a value or a block" if value == NULL_VALUE
        next_value = value
      end
      executor_proxy.load(item: item, value: next_value)
    end
  end
end
