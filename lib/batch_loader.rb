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

  NoBatchError = Class.new(StandardError)

  def self.for(item)
    new(item: item)
  end

  def initialize(item:, executor_proxy: nil)
    @item = item
    @__executor_proxy = executor_proxy
  end

  def batch(default_value: nil, cache: true, replace_methods: nil, key: nil, &batch_block)
    @default_value = default_value
    @cache = cache
    @replace_methods = replace_methods.nil? ? cache : replace_methods
    @key = key
    @batch_block = batch_block

    __executor_proxy.add(item: @item)

    __singleton_class.class_eval { undef_method(:batch) }

    self
  end

  def respond_to?(method_name, include_private = false)
    return true if LEFT_INSTANCE_METHODS.include?(method_name)

    __loaded_value.respond_to?(method_name, include_private)
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

  def __loaded_value
    result = __sync!
    @cache ? @loaded_value : result
  end

  def method_missing(method_name, *args, &block)
    __sync!.public_send(method_name, *args, &block)
  end

  def __sync!
    loaded_value = __sync

    if @replace_methods
      __replace_with!(loaded_value)
    else
      loaded_value
    end
  end

  def __ensure_batched
    return if __executor_proxy.value_loaded?(item: @item)

    items = __executor_proxy.list_items
    loader = __loader
    args = {default_value: @default_value, cache: @cache, replace_methods: @replace_methods, key: @key}
    @batch_block.call(items, loader, args)
    items.each do |item|
      next if __executor_proxy.value_loaded?(item: item)
      loader.call(item, @default_value)
    end
    __executor_proxy.delete(items: items)
  end

  def __loader
    mutex = Mutex.new
    -> (item, value = (no_value = true; nil), &block) do
      if no_value && !block
        raise ArgumentError, "Please pass a value or a block"
      elsif block && !no_value
        raise ArgumentError, "Please pass a value or a block, not both"
      end

      mutex.synchronize do
        next_value = block ? block.call(__executor_proxy.loaded_value(item: item)) : value
        __executor_proxy.load(item: item, value: next_value)
      end
    end
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
      BatchLoader::ExecutorProxy.new(@default_value, @key, &@batch_block)
    end
  end

  (instance_methods - IMPLEMENTED_INSTANCE_METHODS).each { |method_name| undef_method(method_name) }
end
