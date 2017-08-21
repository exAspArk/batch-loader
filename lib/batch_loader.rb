# frozen_string_literal: true

require "batch_loader/version"
require "batch_loader/executor_proxy"
require "batch_loader/middleware"
require "batch_loader/graphql"

class BatchLoader
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
    items.each { |item| loader.call(item, nil) }
    @batch_block.call(items, loader)
    executor_proxy.delete(items: items)
  end

  def singleton_class
    class << self
      self
    end
  end

  def replace_with!(value)
    BatchLoader.send(:without_warnings) do
      ignore_method_names = %i[singleton_method_added].freeze
      singleton_class.class_eval do
        (value.methods - ignore_method_names).each do |method_name|
          define_method(method_name) do |*args, &block|
            value.public_send(method_name, *args, &block)
          end
        end
      end
    end
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

  class << self
    private

    def without_warnings(&block)
      warning_level = $VERBOSE
      $VERBOSE = nil
      block.call
      $VERBOSE = warning_level
    end
  end

  without_warnings do
    leave_method_names = %i[batch batch_loader? respond_to?].freeze
    (instance_methods - leave_method_names).each { |method_name| undef_method(method_name) }
  end
end
