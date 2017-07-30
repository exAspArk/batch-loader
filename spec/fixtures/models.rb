class Post
  def initialize(user_id:)
    @user_id = user_id
  end

  def user_batch_loader
    BatchLoader.for(@user_id).batch do |user_ids, batch_loader|
      User.where(id: user_ids).each do |user|
        batch_loader.load(user.id, user)
      end
    end
  end

  def user
    user_batch_loader.sync
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

  attr_reader :id

  def initialize(id:)
    @id = id
  end
end
