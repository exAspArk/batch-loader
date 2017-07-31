class BatchLoader
  class Middleware
    def initialize(app)
      @app = app
    end

    def call(env)
      begin
        BatchLoader::Executor.ensure_current
        @app.call(env)
      ensure
        BatchLoader::Executor.delete_current
      end
    end
  end
end
