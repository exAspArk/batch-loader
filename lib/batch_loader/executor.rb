# frozen_string_literal: true

class BatchLoader
  class Executor
    NAMESPACE = :batch_loader

    def self.ensure_current
      Thread.current[NAMESPACE] ||= new
    end

    def self.current
      Thread.current[NAMESPACE]
    end

    def self.clear_current
      Thread.current[NAMESPACE] = nil
    end

    attr_reader :items_by_block, :loaded_values_by_block

    def initialize
      @items_by_block = Hash.new { |hash, key| hash[key] = Set.new }
      @loaded_values_by_block = Hash.new { |hash, key| hash[key] = {} }
    end
  end
end
