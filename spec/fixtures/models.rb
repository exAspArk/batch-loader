class Post
  attr_accessor :user_id

  def self.save(user_id:)
    @@posts ||= []
    @@posts << new(user_id: user_id)
  end

  def self.all
    @@posts
  end

  def self.destroy_all
    @@posts = []
  end

  def initialize(user_id:)
    self.user_id = user_id
  end

  def user_lazy(cache: true)
    BatchLoader.for(user_id).batch(cache: cache) do |user_ids, loader|
      User.where(id: user_ids).each { |user| loader.call(user.id, user) }
    end
  end
end

class User
  def self.save(id:)
    @@users ||= {}
    @@users[id] = new(id: id)
  end

  def self.where(id:)
    @@users.each_with_object([]) { |(k, v), memo| memo << v if id.include?(k) }
  end

  def self.destroy_all
    @@users = {}
  end

  attr_reader :id

  def initialize(id:)
    @id = id
  end
end
