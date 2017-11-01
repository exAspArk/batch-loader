# frozen_string_literal: true

require "set"

require_relative "./batch_loader/version"
require_relative "./batch_loader/executor_proxy"
require_relative "./batch_loader/middleware"
require_relative "./batch_loader/graphql"

class BatchLoader
  IMPLEMENTED_INSTANCE_METHODS = %i[object_id __id__ __send__ singleton_method_added __sync respond_to? batch inspect].freeze
  REPLACABLE_INSTANCE_METHODS = %i[batch inspect].freeze
  LEFT_INSTANCE_METHODS = (IMPLEMENTED_INSTANCE_METHODS - REPLACABLE_INSTANCE_METHODS).freeze
  NULL_VALUE = :batch_loader_null

  NoBatchError = Class.new(StandardError)

  def self.for(item)
    new(item: item)
  end

  def initialize(item:)
    @item = item
  end

  def batch(default_value: nil, cache: true, &batch_block)
    @default_value = default_value
    @cache = cache
    @batch_block = batch_block
    __executor_proxy.add(item: @item)

    __singleton_class.class_eval { undef_method(:batch) }

    self
  end

  def respond_to?(method_name, include_private = false)
    LEFT_INSTANCE_METHODS.include?(method_name) || method_missing(:respond_to?, method_name, include_private)
  end

  def inspect
    "#<BatchLoader:0x#{(object_id << 1)}>"
  end

  def __sync
    return @loaded_value if @synced

    __ensure_batched
    @loaded_value = __executor_proxy.loaded_value(item: @item)

    if @cache
      @synced = true
    else
      __purge_cache
    end

    @loaded_value
  end

  private

  def method_missing(method_name, *args, &block)
    __sync!.public_send(method_name, *args, &block)
  end

  def __sync!
    loaded_value = __sync

    if @cache
      __replace_with!(loaded_value)
    else
      loaded_value
    end
  end

  def __ensure_batched
    return if __executor_proxy.value_loaded?(item: @item)

    items = __executor_proxy.list_items
    loader =  -> (item, value = NULL_VALUE, &block) {
      if block
        raise ArgumentError, "Please pass a value or a block, not both" if value != NULL_VALUE
        next_value = block.call(__executor_proxy.loaded_value(item: item))
      else
        next_value = value
      end
      __executor_proxy.load(item: item, value: next_value)
    }

    @batch_block.call(items, loader)
    items.each do |item|
      next if __executor_proxy.value_loaded?(item: item)
      loader.call(item, @default_value)
    end
    __executor_proxy.delete(items: items)
  end

  def __singleton_class
    class << self ; self ; end
  end

  def __replace_with!(value)
    __singleton_class.class_eval do
      (value.methods - LEFT_INSTANCE_METHODS).each do |method_name|
        define_method(method_name) do |*args, &block|
          value.public_send(method_name, *args, &block)
        end
      end
    end

    self
  end

  def __purge_cache
    __executor_proxy.unload_value(item: @item)
    __executor_proxy.add(item: @item)
  end

  def __executor_proxy
    @__executor_proxy ||= begin
      raise NoBatchError.new("Please provide a batch block first") unless @batch_block
      BatchLoader::ExecutorProxy.new(@default_value, &@batch_block)
    end
  end

  (instance_methods - IMPLEMENTED_INSTANCE_METHODS).each { |method_name| undef_method(method_name) }
end
