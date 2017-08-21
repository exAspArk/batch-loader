UserType = GraphQL::ObjectType.define do
  name "User"
  field :id, !types.ID
end

PostType = GraphQL::ObjectType.define do
  name "Post"
  field :user, !UserType, resolve: ->(post, args, ctx) { post.user_lazy }
end

QueryType = GraphQL::ObjectType.define do
  name "Query"
  field :posts, !types[PostType], resolve: ->(obj, args, ctx) { Post.all }
end

GraphqlSchema = GraphQL::Schema.define do
  query QueryType
  use BatchLoader::GraphQL
end
