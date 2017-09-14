# frozen_string_literal: true

require "set"
require "forwardable"

require "batch_loader/version"
require "batch_loader/executor_proxy"
require "batch_loader/middleware"
require "batch_loader/graphql"

class BatchLoader
  extend Forwardable

  INSTANCE_METHOD_NAMES = %i[
    object_id
    __id__
    __send__
    singleton_method_added
    batch
    batch_loader?
    respond_to?
  ].freeze

  NoBatchError = Class.new(StandardError)

  def self.for(item)
    new(item: item)
  end

  def initialize(item:)
    @item = item
  end

  def batch(cache: true, &batch_block)
    @cache = cache
    @batch_block = batch_block
    executor_proxy.add(item: @item)

    singleton_class.class_eval { undef_method(:batch) }

    self
  end

  def batch_loader?
    true
  end

  def respond_to?(method_name)
    method_name == :batch_loader? || method_missing(:respond_to?, method_name)
  end

  private

  def method_missing(method_name, *args, &block)
    sync!.public_send(method_name, *args, &block)
  end

  def sync!
    return self if @synced

    ensure_batched
    loaded_value = executor_proxy.loaded_value(item: @item)

    if @cache
      replace_with!(loaded_value)
      @synced = true
      self
    else
      purge_cache
      loaded_value
    end
  end

  def ensure_batched
    return if executor_proxy.value_loaded?(item: @item)

    items = executor_proxy.list_items
    loader = ->(item, value) { executor_proxy.load(item: item, value: value) }
    @batch_block.call(items, loader)

    items.each do |item|
      next if executor_proxy.value_loaded?(item: item)
      loader.call(item, nil) # use "nil" for unloaded item after succesfull batching
    end

    executor_proxy.delete(items: items)
  end

  def singleton_class
    class << self
      self
    end
  end

  def replace_with!(value)
    @loaded_value = value
    singleton_class.class_eval { def_delegators :@loaded_value, *(value.methods - INSTANCE_METHOD_NAMES) }
  end

  def purge_cache
    executor_proxy.unload_value(item: @item)
    executor_proxy.add(item: @item)
  end

  def executor_proxy
    @executor_proxy ||= begin
      raise NoBatchError.new("Please provide a batch block first") unless @batch_block
      BatchLoader::ExecutorProxy.new(&@batch_block)
    end
  end

  (instance_methods - INSTANCE_METHOD_NAMES).each { |method_name| undef_method(method_name) }
end
