class Post
  attr_accessor :user_id, :title

  class << self
    def save(user_id:, title: nil)
      ensure_init_store
      new(user_id: user_id, title: title).tap { |post| @posts << post }
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

  def initialize(user_id:, title: nil)
    self.user_id = user_id
    self.title = title || "Untitled"
  end

  def user_lazy(**opts)
    BatchLoader.for(user_id).batch(**opts) do |user_ids, loader|
      User.where(id: user_ids).each { |user| loader.call(user.id, user) }
    end
  end
end

class User
  class << self
    def save(id:)
      ensure_init_store
      @store[self][id] = new(id: id)
    end

    def where(id:)
      ensure_init_store
      @store[self].each_with_object([]) { |(k, v), memo| memo << v if id.include?(k) }
    end

    def destroy_all
      ensure_init_store
      @store[self] = {}
    end

    private

    def ensure_init_store
      @store ||= Hash.new { |h, k| h[k] = {} }
    end
  end

  attr_reader :id

  def initialize(id:)
    @id = id
  end

  def batch
    "Batch from User"
  end

  def hash
    [User, id].hash
  end

  def posts
    Post.all.select { |p| p.user_id == id }
  end

  def eql?(other)
    other.is_a?(User) && id == other.id
  end

  private

  def some_private_method
  end
end

class Author < User
end

class Reader < User
end
