require "spec_helper"

RSpec.describe BatchLoader::Middleware do
  describe '#call' do
    it 'returns the result from the app' do
      app = ->(_env) { 1 }
      middleware = BatchLoader::Middleware.new(app)

      expect(middleware.call(nil)).to eq(1)
    end

    it 'clears the Executor' do
      app = ->(_) { nil }
      middleware = BatchLoader::Middleware.new(app)
      BatchLoader::Executor.ensure_current

      expect {
        middleware.call(nil)
      }.to change {
        BatchLoader::Executor.current
      }.to(nil)
    end
  end
end
