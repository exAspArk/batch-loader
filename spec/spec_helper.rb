require "bundler/setup"

require "graphql"

require "batch_loader"

require "fixtures/models"
require "fixtures/graphql_schema"

if ENV['CI']
  require 'coveralls'
  Coveralls.wear!
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.after do
    BatchLoader::Executor.clear_current
  end
end
