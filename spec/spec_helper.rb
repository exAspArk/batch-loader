require "bundler/setup"

if ENV['CI']
  require 'coveralls'
  Coveralls.wear!
end

require "batch_loader"

require "graphql"
require "fixtures/models"
require "fixtures/graphql_schema"

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
