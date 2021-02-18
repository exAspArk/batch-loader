class UserType < GraphQL::Schema::Object
  field :id, ID, null: false
end

class PostType < GraphQL::Schema::Object
  field :user, UserType, null: false
  field :user_old, UserType, null: false

  def user
    BatchLoader::GraphQL.for(object.user_id).batch(default_value: nil) do |user_ids, loader|
      User.where(id: user_ids).each { |user| loader.call(user.id, user) }
    end
  end

  def user_old
    BatchLoader.for(object.user_id).batch(default_value: nil) do |user_ids, loader|
      User.where(id: user_ids).each { |user| loader.call(user.id, user) }
    end
  end
end

class QueryType < GraphQL::Schema::Object
  field :posts, [PostType], null: false

  def posts
    Post.all
  end
end

class GraphqlSchema < GraphQL::Schema
  query QueryType
  use BatchLoader::GraphQL
end

if defined?(GraphQL::Execution::Interpreter)
  class GraphqlSchemaWithInterpreter < GraphQL::Schema
    use GraphQL::Execution::Interpreter
    use GraphQL::Analysis::AST
    query QueryType
    use BatchLoader::GraphQL
  end
end
