# frozen_string_literal: true

class BatchLoader
  class GraphQL
    def self.use(schema_definition)
      schema_definition.lazy_resolve(BatchLoader::GraphQL, :sync)

      # in cases when BatchLoader is being used instead of BatchLoader::GraphQL
      if schema_definition.respond_to?(:interpreter?) && schema_definition.interpreter?
        schema_definition.tracer(self)
      else
        schema_definition.instrument(:field, self)
      end
    end

    def self.trace(event, _data)
      if event == 'execute_field'
        result = yield
        result.respond_to?(:__sync) ? wrap_with_warning(result) : result
      else
        yield
      end
    end

    def self.instrument(type, field)
      old_resolve_proc = field.resolve_proc
      new_resolve_proc = ->(object, arguments, context) do
        result = old_resolve_proc.call(object, arguments, context)
        result.respond_to?(:__sync) ? wrap_with_warning(result) : result
      end

      field.redefine { resolve(new_resolve_proc) }
    end

    def self.wrap_with_warning(batch_loader)
      warn "DEPRECATION WARNING: using BatchLoader.for in GraphQL is deprecated. Use BatchLoader::GraphQL.for instead or return BatchLoader::GraphQL.wrap from your resolver."
      wrap(batch_loader)
    end
    private_class_method :wrap_with_warning

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
