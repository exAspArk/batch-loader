require "spec_helper"

RSpec.describe 'GraphQL integration' do
  it 'resolves BatchLoader fields lazily' do
    user1 = User.save(id: "1")
    user2 = User.save(id: "2")
    Post.save(user_id: user1.id)
    Post.save(user_id: user2.id)
    query = <<~QUERY
      {
        posts {
          user { id }
          userOld { id }
        }
      }
    QUERY

    expect(User).to receive(:where).with(id: ["1", "2"]).twice.and_call_original

    result = GraphqlSchema.execute(query)

    expect(result['data']).to eq({
      'posts' => [
        {'user' => {'id' => "1"}, 'userOld' => {'id' => "1"}},
        {'user' => {'id' => "2"}, 'userOld' => {'id' => "2"}}
      ]
    })
  end
end
