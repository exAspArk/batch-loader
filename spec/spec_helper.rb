require "bundler/setup"

ENV['GRAPHQL_RUBY_VERSION'] ||= '1_8'

if ENV['CI']
  require 'coveralls'
  Coveralls.wear!
end

require_relative "../lib/batch_loader"

require "graphql"
require_relative "./fixtures/models"
require_relative "./fixtures/graphql_schema"

class SlowExecutorProxy < BatchLoader::ExecutorProxy
  def value_loaded?(item:)
    result = loaded.key?(item)
    sleep 0.5
    result
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.order = :random

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.after do
    BatchLoader::Executor.clear_current
  end
end
