require "spec_helper"

RSpec.describe BatchLoader do
  it "has a version number" do
    expect(BatchLoader::VERSION).not_to be nil
  end

  it "does something useful" do
    user1 = User.save(id: 1)
    post1 = Post.new(user_id: user1.id)
    user2 = User.save(id: 2)
    post2 = Post.new(user_id: user2.id)
    result = {user1: post1.user_batch_loader, user2: post2.user_batch_loader}

    expect(User).to receive(:where).with(id: [1, 2]).once.and_call_original

    BatchLoader.sync!(result)

    expect(result).to eq(user1: user1, user2: user2)
  end
end
