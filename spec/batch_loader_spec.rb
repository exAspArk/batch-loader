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

  context 'with custom key' do
    it 'batches multiple items by key' do
      author = Author.save(id: 1)
      reader = Reader.save(id: 2)
      batch_loader = ->(type, id) do
        BatchLoader.for(id).batch(key: type) do |ids, loader, args|
          args[:key].where(id: ids).each { |user| loader.call(user.id, user) }
        end
      end

      loader_author = batch_loader.call(Author, 1)
      loader_reader = batch_loader.call(Reader, 2)

      expect(Author).to receive(:where).with(id: [1]).once.and_call_original
      expect(loader_author).to eq(author)
      expect(Reader).to receive(:where).with(id: [2]).once.and_call_original
      expect(loader_reader).to eq(reader)
    end

    it 'batches multiple items with hash-identical keys' do
      user = Author.new(id: 1)
      same_user = Reader.new(id: 1)
      other_user = Reader.new(id: 2)

      post_1 = Post.save(user_id: 1, title: "First post")
      post_2 = Post.save(user_id: 1, title: "Second post")
      post_3 = Post.save(user_id: 2, title: "First post")

      batch_loader = ->(user, title) do
        BatchLoader.for(title).batch(key: user) do |titles, loader, args|
          args[:key].posts.select { |p| titles.include?(p.title) }.each { |post| loader.call(post.title, post) }
        end
      end

      loader_1 = batch_loader.call(user, "First post")
      loader_2 = batch_loader.call(same_user, "Second post")
      loader_3 = batch_loader.call(other_user, "First post")

      expect(user).to receive(:posts).once.and_call_original
      expect(same_user).not_to receive(:posts)
      expect(other_user).to receive(:posts).once.and_call_original

      expect(loader_1).to eq(post_1)
      expect(loader_2).to eq(post_2)
      expect(loader_3).to eq(post_3)
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

  context 'instance' do
    it 'works for methods with kwargs in Ruby 3' do
      user = User.save(id: 1)
      post = Post.new(user_id: user.id)

      batch_loader = post.user_lazy

      expect(batch_loader.method_with_arg_kwarg_and_block(1, b: 2) { |a, b| a + b }).to eq(3)
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
    let(:user) { User.save(id: 1) }
    let(:post) { Post.new(user_id: user.id) }

    subject { post.user_lazy }

    it 'syncs the object just once' do
      loaded_user = post.user_lazy

      expect(loaded_user.respond_to?(:id)).to eq(true)
    end

    it 'returns false for private methods by default' do
      expect(subject.respond_to?(:some_private_method)).to eq(false)
    end

    it 'returns true for private methods if include_private flag is true' do
      expect(subject.respond_to?(:some_private_method, true)).to eq(true)
    end

    it 'does not depend on the loaded value #method_missing' do
      expect(user).not_to receive(:method_missing)

      expect(subject).to respond_to(:id)
    end

    context 'when the cache and method replacement is disabled' do
      it 'syncs the object on every call' do
        loaded_user = post.user_lazy(cache: false, replace_methods: false)

        expect(User).to receive(:where).with(id: [1]).twice.and_call_original

        loaded_user.respond_to?(:id)
        loaded_user.respond_to?(:id)
      end
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

    it 'works without cache and method replacement for the same BatchLoader instance' do
      user = User.save(id: 1)
      post = Post.new(user_id: user.id)
      user_lazy = post.user_lazy(cache: false, replace_methods: false)

      expect(User).to receive(:where).with(id: [1]).twice.and_call_original

      expect(user_lazy).to eq(user)
      expect(user_lazy).to eq(user)
    end

    it 'does not replace methods when replace_methods is false' do
      user = User.save(id: 1)
      post = Post.new(user_id: user.id)
      user_lazy = post.user_lazy(cache: true, replace_methods: false)

      expect(user_lazy).to receive(:method_missing).and_call_original

      user_lazy.id
    end

    it 'does not allow mutating a list of items' do
      batch_loader = BatchLoader.for(1).batch do |items, loader|
        items.map! { |i| i - 1 }
      end

      expect { batch_loader.to_s }.to raise_error(RuntimeError, /\Acan't modify frozen Array/)
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
