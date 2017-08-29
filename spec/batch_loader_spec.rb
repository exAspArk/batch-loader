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
  end

  describe '#batch_loader?' do
    it 'always returns true' do
      user = User.save(id: 1)
      post = Post.new(user_id: user.id)

      expect(post.user_lazy.batch_loader?).to eq(true)
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
  end
end
