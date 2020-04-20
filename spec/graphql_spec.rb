require "spec_helper"

RSpec.describe 'GraphQL integration' do
  after do
    User.destroy_all
    Post.destroy_all
  end

  it 'resolves BatchLoader fields lazily' do
    test(GraphqlSchema)
  end

  if defined?(GraphqlSchemaWithInterpreter)
    it 'resolves BatchLoader fields lazily with GraphQL Interpreter' do
      test(GraphqlSchemaWithInterpreter)
    end
  end

  def test(schema)
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

    result = schema.execute(query)

    expect(result['data']).to eq({
      'posts' => [
        {'user' => {'id' => "1"}, 'userOld' => {'id' => "1"}},
        {'user' => {'id' => "2"}, 'userOld' => {'id' => "2"}}
      ]
    })
  end
end
