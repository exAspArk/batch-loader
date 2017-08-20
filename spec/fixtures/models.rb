class Post
  attr_accessor :user_id

  class << self
    def save(user_id:)
      ensure_init_store
      @posts << new(user_id: user_id)
    end

    def all
      ensure_init_store
      @posts
    end

    def destroy_all
      @posts = []
    end

    private

    def ensure_init_store
      @posts ||= []
    end
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
  class << self
    def save(id:)
      ensure_init_store
      @users[id] = new(id: id)
    end

    def where(id:)
      ensure_init_store
      @users.each_with_object([]) { |(k, v), memo| memo << v if id.include?(k) }
    end

    def destroy_all
      @users = {}
    end

    private

    def ensure_init_store
      @users ||= {}
    end
  end

  attr_reader :id

  def initialize(id:)
    @id = id
  end
end
