# frozen_string_literal: true

class BatchLoader
  class GraphQL
    class Wrapper
      def initialize(batch_loader)
        @batch_loader = batch_loader
      end

      def sync
        @batch_loader.__sync
      end
    end

    def self.use(schema_definition)
      schema_definition.lazy_resolve(BatchLoader::GraphQL::Wrapper, :sync)
      schema_definition.instrument(:field, self)
    end

    def self.instrument(type, field)
      old_resolve_proc = field.resolve_proc
      new_resolve_proc = ->(object, arguments, context) do
        result = old_resolve_proc.call(object, arguments, context)
        result.respond_to?(:__sync) ? BatchLoader::GraphQL::Wrapper.new(result) : result
      end

      field.redefine { resolve(new_resolve_proc) }
    end
  end
end
