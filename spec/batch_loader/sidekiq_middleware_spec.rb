require "spec_helper"

RSpec.describe BatchLoader::SidekiqMiddleware do
  describe '#call' do
    it 'returns the result from the app' do
      middleware = BatchLoader::SidekiqMiddleware.new
      expect( middleware.call(nil, nil, nil) { 1 }).to eq(1)
    end

    it 'clears the Executor' do
      middleware = BatchLoader::SidekiqMiddleware.new
      BatchLoader::Executor.ensure_current

      expect {
        middleware.call(nil, nil, nil) { 1 }
      }.to change {
        BatchLoader::Executor.current
      }.to(nil)
    end
  end
end
