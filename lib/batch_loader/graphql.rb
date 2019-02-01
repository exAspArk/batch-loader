# frozen_string_literal: true

class BatchLoader
  class GraphQL
    def self.use(schema_definition)
      schema_definition.lazy_resolve(BatchLoader::GraphQL, :sync)
      # for graphql gem versions <= 1.8.6 which work with BatchLoader instead of BatchLoader::GraphQL
      schema_definition.instrument(:field, self)
    end

    def self.instrument(type, field)
      old_resolve_proc = field.resolve_proc
      new_resolve_proc = ->(object, arguments, context) do
        result = old_resolve_proc.call(object, arguments, context)
        result.respond_to?(:__sync) ? BatchLoader::GraphQL.wrap(result) : result
      end

      field.redefine { resolve(new_resolve_proc) }
    end

    def self.wrap(batch_loader)
      BatchLoader::GraphQL.new.tap do |graphql|
        graphql.batch_loader = batch_loader
      end
    end

    def self.for(item)
      new(item)
    end

    attr_writer :batch_loader

    def initialize(item = nil)
      @batch_loader = BatchLoader.for(item)
    end

    def batch(*args, &block)
      @batch_loader.batch(*args, &block)
      self
    end

    def sync
      @batch_loader.__sync
    end
  end
end
