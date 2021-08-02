# frozen_string_literal: true

class BatchLoader
  class SidekiqMiddleware
    def call(_worker, _job, _queue)
      yield
    ensure
      BatchLoader::Executor.clear_current
    end
  end
end
