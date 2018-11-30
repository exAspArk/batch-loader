case ENV['GRAPHQL_RUBY_VERSION']
when '1_7'
  UserType = GraphQL::ObjectType.define do
    name "User"
    field :id, !types.ID
  end

  PostType = GraphQL::ObjectType.define do
    name "Post"
    field :user, !UserType, resolve: ->(object, args, ctx) { object.user_lazy }
    field :userId, !types.Int, resolve: ->(object, args, ctx) do
      BatchLoader.for(object).batch do |posts, loader|
        posts.each { |p| loader.call(p, p.user_lazy.id) }
      end
    end
  end

  QueryType = GraphQL::ObjectType.define do
    name "Query"
    field :posts, !types[PostType], resolve: ->(obj, args, ctx) { Post.all }
  end

  GraphqlSchema = GraphQL::Schema.define do
    query QueryType
    use BatchLoader::GraphQL
  end
when '1_8'
  class UserType < GraphQL::Schema::Object
    field :id, ID, null: false
  end

  class PostType < GraphQL::Schema::Object
    field :user, UserType, null: false
    field :user_id, Int, null: false

    def user
      object.user_lazy
    end

    def user_id
      BatchLoader.for(object).batch do |posts, loader|
        posts.each { |p| loader.call(p, p.user_lazy.id) }
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
end
