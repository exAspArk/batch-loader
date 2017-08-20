# frozen_string_literal: true

class BatchLoader
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      begin
        @app.call(env)
      ensure
        BatchLoader::Executor.clear_current
      end
    end
  end
end
