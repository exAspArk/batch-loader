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

class ResourceBase
  class << self
    def save(id:)
      ensure_init_store
      @resources[id] = new(id: id)
    end

    def where(id:)
      ensure_init_store
      @resources.each_with_object([]) { |(k, v), memo| memo << v if id.include?(k) }
    end

    def destroy_all
      @resources = {}
    end

    private

    def ensure_init_store
      @resources ||= {}
    end
  end

  attr_reader :id

  def initialize(id:)
    @id = id
  end
end

class User < ResourceBase
  def batch
    "Batch from User"
  end

  private

  def some_private_method
    :some_private_method
  end
end

class Role < ResourceBase
end
