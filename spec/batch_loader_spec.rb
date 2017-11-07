require "spec_helper"

RSpec.describe BatchLoader do
  after do
    User.destroy_all
    Post.destroy_all
  end

  context 'lazily' do
    it "syncs all BatchLoaders by returning the loaded value" do
      user1 = User.save(id: 1)
      post1 = Post.new(user_id: user1.id)
      user2 = User.save(id: 2)
      post2 = Post.new(user_id: user2.id)
      result = {user1: post1.user_lazy, user2: post2.user_lazy}

      expect(User).to receive(:where).with(id: [1, 2]).once.and_call_original

      expect(result).to eq(user1: user1, user2: user2)
    end

    it 'raises an error if batch was not provided' do
      expect {
        BatchLoader.for(1).id
      }.to raise_error(BatchLoader::NoBatchError, "Please provide a batch block first")
    end

    it 'caches the result even between different BatchLoader instances' do
      user = User.save(id: 1)
      post = Post.new(user_id: user.id)

      expect(User).to receive(:where).with(id: [1]).once.and_call_original

      expect(post.user_lazy.id).to eq(user.id)
      expect(post.user_lazy.id).to eq(user.id)
    end

    it 'caches the result for the same BatchLoader instance' do
      user = User.save(id: 1)
      post = Post.new(user_id: user.id)

      expect(User).to receive(:where).with(id: [1]).once.and_call_original

      expect(post.user_lazy).to eq(user)
      expect(post.user_lazy).to eq(user)
    end

    it 'works even if the loaded values is nil' do
      post = Post.new(user_id: 1)

      expect(User).to receive(:where).with(id: [1]).once.and_call_original

      expect(post.user_lazy).to eq(nil)
      expect(post.user_lazy).to eq(nil)
    end

    it 'raises and error if loaded value do not have a method' do
      user = User.save(id: 1)
      post = Post.new(user_id: user.id)

      expect(User).to receive(:where).with(id: [1]).once.and_call_original

      expect { post.user_lazy.foo }.to raise_error(NoMethodError, /undefined method `foo' for #<User/)
    end

    it 'works with nested BatchLoaders' do
      user1 = User.save(id: 1)
      Post.new(user_id: user1.id)
      user2 = User.save(id: 2)
      Post.new(user_id: user2.id)
      nested_batch_loader = ->(id) do
        BatchLoader.for(id).batch do |user_ids, loader|
          User.where(id: user_ids).each { |u| loader.call(u.id, u.id) }
        end
      end
      batch_loader = ->(id) do
        BatchLoader.for(id).batch do |user_ids, loader|
          user_ids.each { |user_id| loader.call(user_id, nested_batch_loader.call(user_id)) }
        end
      end

      expect(User).to receive(:where).with(id: [1, 2]).once.and_call_original

      result = [batch_loader.call(1), batch_loader.call(2)]

      expect(result).to eq([1, 2])
    end
  end

  context 'multi load with meta programming' do
    it 'loads multi items' do
      items = []
      {
        user: { name: 'User', ids: [1, 2, 3, 4, 5] },
        post: { name: 'Post', ids: [2, 3, 4, 1, 2] },
      }.each do |type, kind|
        kind[:ids].map do |id|
          items << BatchLoader.for(id).batch(key: type) do |ids, loader, key|
            ids.each { |item| loader.call(item, OpenStruct.new({name: key}.merge({id: item})) ) }
          end
        end
      end

      expect(items.size).to eq(10)
      expect(items.select { |item| item.name === :user }.map(&:id)).to eq([1, 2, 3, 4, 5])
      expect(items.select { |item| item.name === :post }.map(&:id)).to eq([2, 3, 4, 1, 2])
    end

    it 'with query' do
      User.save(id: 1)
      User.save(id: 2)
      User.save(id: 3)

      Role.save(id: 1)
      Role.save(id: 2)
      Role.save(id: 4)
      Role.save(id: 5)

      items = {}
      {
        user: { name: 'User', ids: [1, 2, 3]},
        role: { name: 'Role', ids: [1, 2, 4, 5]},
      }.each do |type, kind|
        items[type] = []
        kind[:ids].map do |id|
          items[type] << BatchLoader.for(id).batch(key: type, context: kind) do |ids, loader, key, contexts|
            expect(contexts.keys).to eq(ids)
            expect(contexts.map{|k,v|v[:name]}).to eq(Array.new(ids.size, kind[:name]))
            Object.const_get(key.capitalize).where(id: ids).each { |item| loader.call(item.id, item) }
          end
        end
      end

      expect(items).to be_a_kind_of(Hash)
      expect(items[:user].size).to eq(3)
      expect(items[:user].map(&:id)).to eq([1, 2, 3])
      expect(items[:role].size).to eq(4)
      expect(items[:role].map(&:id)).to eq([1, 2, 4, 5])
    end
  end

  context 'loader' do
    it 'loads the data even in a separate thread' do
      lazy = BatchLoader.for(1).batch do |nums, loader|
        threads = nums.map do |num|
          Thread.new { loader.call(num, num + 1) }
        end
        threads.each(&:join)
      end

      expect(lazy).to eq(2)
    end

    it 'is thread-safe' do
      batch_block = Proc.new do |ids, loader|
        ids.each do |id|
          thread = Thread.new { loader.call(id) { |value| value << id } }
          loader.call(id) { |value| value << id + 1 }
          thread.join
        end
      end
      slow_executor_proxy = SlowExecutorProxy.new([], nil, &batch_block)
      lazy = BatchLoader.new(item: 1, executor_proxy: slow_executor_proxy).batch(default_value: [], &batch_block)

      expect(lazy).to match_array([1, 2])
    end

    it 'supports alternative default values' do
      lazy = BatchLoader.for(1).batch(default_value: 123) do |nums, loader|
        # No-op, so default is returned
      end

      expect(lazy).to eq(123)
    end

    it 'supports memoizing repeated calls to the same item, via a block' do
      lazy = BatchLoader.for(1).batch(default_value: []) do |nums, loader|
        nums.each do |num|
          loader.call(num) { |memo| memo.push(num) }
          loader.call(num) { |memo| memo.push(num + 1) }
          loader.call(num) { |memo| memo.push(num + 2) }
        end
      end

      expect(lazy).to eq([1,2,3])
    end

    it 'raises ArgumentError if called with block and value' do
      lazy = BatchLoader.for(1).batch do |nums, loader|
        nums.each do |num|
          loader.call(num, "one value") { "too many values" }
        end
      end

      expect { lazy.sync }.to raise_error(ArgumentError)
    end

    it 'raises ArgumentError if called without block and value' do
      lazy = BatchLoader.for(1).batch do |nums, loader|
        nums.each { |num| loader.call(num) }
      end

      expect { lazy.sync }.to raise_error(ArgumentError)
    end
  end

  describe '#inspect' do
    it 'returns BatchLoader without syncing and delegates #inspect after' do
      user = User.save(id: 1)
      post = Post.new(user_id: user.id)

      batch_loader = post.user_lazy

      expect(batch_loader.inspect).to match(/#<BatchLoader:0x\w+>/)
      expect(batch_loader.to_s).to match(/#<User:0x\w+>/)
      expect(batch_loader.inspect).to match(/#<User:0x\w+ @id=1>/)
    end
  end

  describe '#respond_to?' do
    it 'returns false for private methods by default' do
      user = User.save(id: 1)
      post = Post.new(user_id: user.id)

      batch_loader = post.user_lazy

      expect(batch_loader.respond_to?(:some_private_method)).to eq(false)
    end

    it 'returns true for private methods if include_private flag is true' do
      user = User.save(id: 1)
      post = Post.new(user_id: user.id)

      batch_loader = post.user_lazy

      expect(batch_loader.respond_to?(:some_private_method, true)).to eq(true)
    end
  end

  describe '#batch' do
    it 'delegates the second batch call to the loaded value' do
      user = User.save(id: 1)
      post = Post.new(user_id: user.id)

      expect(post.user_lazy.batch).to eq("Batch from User")
    end

    it 'works without cache between different BatchLoader instances for the same item' do
      user1 = User.save(id: 1)
      user2 = User.save(id: 2)
      post = Post.new(user_id: user1.id)

      expect(User).to receive(:where).with(id: [1]).once.and_call_original
      expect(post.user_lazy).to eq(user1)

      post.user_id = user2.id

      expect(User).to receive(:where).with(id: [2]).once.and_call_original
      expect(post.user_lazy(cache: false)).to eq(user2)
    end

    it 'works without cache for the same BatchLoader instance' do
      user = User.save(id: 1)
      post = Post.new(user_id: user.id)
      user_lazy = post.user_lazy(cache: false)

      expect(User).to receive(:where).with(id: [1]).twice.and_call_original

      expect(user_lazy).to eq(user)
      expect(user_lazy).to eq(user)
    end

    it 'raises the error if something went wrong in the batch' do
      result = BatchLoader.for(1).batch { |ids, loader| raise "Oops" }
      # should work event with Pry which currently shallows errors on #inspect call https://github.com/pry/pry/issues/1642
      # require 'pry'; binding.pry
      expect { result.to_s }.to raise_error("Oops")
      expect { result.to_s }.to raise_error("Oops")
    end
  end
end
