class Topic
  include MongoMapper::Document
  include MongoMapperExt::Slugizer
  include MongoMapperExt::Filter
  include Support::Versionable
  include Support::Search::Searchable

  key :title, String, :required => true, :index => true, :unique => true
  filterable_keys :title
  key :description, String
  key :questions_count, :default => 0

  key :updated_by_id, String
  belongs_to :updated_by, :class_name => "User"

  key :follower_ids, Array, :index => true
  has_many :followers, :class_name => 'User', :in => :follower_ids
  key :followers_count, :default => 0

  slug_key :title, :unique => true, :min_length => 3

  has_many :news_items, :foreign_key => :recipient_id, :dependent => :destroy

  key :related_topic_ids, :default => []
  has_many :related_topics, :class_name => "Topic",
    :in => :related_topic_ids

  timestamps!

  versionable_keys :title, :description

  before_validation :trim_spaces

  before_save :generate_slug

  after_destroy :remove_from_suggestions

  # Removes spaces from the beginning, the end and inbetween words
  # from the title
  def trim_spaces
    self.title.strip!
    self.title.sub!(/\s+/, " ")
  end

  # Takes array of strings and returns array of topics with matching
  # titles, creating new topics for titles that are not found.
  def self.from_titles!(titles)
    return [] if titles.blank?
    self.all(:title.in => titles).tap { |topics|
      if topics.size != titles.size
        new_titles = titles - topics.map(&:title)
        new_topics = new_titles.map {|t| self.create(:title => t) }
        topics.push(*new_topics)
      end
    }
  end

  def name
    title
  end

  def find_related_topics
    topic_counts = {}

    Question.query(:topic_ids => self.id).each do |question|
      question.topics.each do |related_topic|
        next if related_topic == self
        topic_counts[related_topic.id] =
          (topic_counts[related_topic.id] || 0) + 1
      end
    end

    self.related_topic_ids =
      topic_counts.to_a.sort{|a, b| -(a[1] <=> b[1])}[0 .. 9].map(&:first)

    self.related_topics
  end

  # Add a follower to topic.
  def add_follower!(user)
    if !self.followers.include?(user)
      self.followers << user
      self.save!
      self.increment(:followers_count => 1)
    end
  end

  # Remove a follower from topic.
  def remove_follower!(user)
    if self.followers.include?(user)
      self.follower_ids.delete(user.id)
      self.save!
      self.increment(:followers_count => -1)
    end
  end

  # Merges other to self: self receives every question, follower and
  # news update from other. Destroys other. Cannot be undone.
  def merge_with!(other)
    return false if id == other.id

    other.followers.each do |f|
      self.add_follower!(f)
    end

    Question.query(:topic_ids => other.id).each do |q|
      q.classify! self
    end

    # TODO: check whether this is actually safe.
    other.news_items.each do |item|
      if NewsItem.query(:recipient_id => id,
                         :recipient_type => "Topic",
                         :news_update_id => item.id).count == 0
        item.recipient = self
        item.save
      end
    end

    NewsItem.query(:origin_id => other.id, :origin_type => "Topic").each do |item|
      item.origin = self
      item.save
    end

    other.destroy
    save
  end

  # Removes topic from user suggestions and ignored topics. This
  # method is delayed in production and staging environments.
  def remove_from_suggestions
    Suggestion.query(:entry_id => self.id,
                     :entry_type => "Topic").each do |suggestion|
      suggestion.user.remove_suggestion(suggestion)
      suggestion.user.save
    end

    # TODO: We should replace this with a better query, but this would
    # incur on changes in the models. Right now this isn't too much of
    # an issue since topics are rarely deleted.
    User.query(:select => :suggestion_list).each do |user|
      if user.suggestion_list
        user.suggestion_list.uninteresting_topic_ids.delete(self.id)
        user.save
      end
    end
  end

  def unanswered_questions_count
    return Question.count(:topic_ids => self.id, :banned => false,
                           :closed => false, :answered_with_id => nil,
                           :exercise.ne => true)
  end

  # WARNING: The search index update isn't atomic: the models will be
  # consistent, but the search index might not reflect the actual
  # questions_count.
  def increment_questions_count(step = 1)
    self.increment(:questions_count => step)
    self.questions_count += step
    self.update_search_index(true)
  end

  def search_entry
    {
      :id => self.id,
      :title => self.title,
      :entry_type => "Topic",
      :question_count => self.questions_count
    }
  end

  def needs_to_update_search_index?
    # Normally, we would need to check here whether questions_count
    # has changed or not, but since updates in questions_count are
    # done via mongo's atomic operations, we update this on questions.

    if self.title_changed?
      self.update_questions_search_entries
      true
    end
  end

  # Change the topic field on the search entries of this topic's
  # questions.
  def update_questions_search_entries
    Question.query(:topic_ids => self.id).each do |question|
      question.update_search_index(true)
    end
  end
  handle_asynchronously :update_questions_search_entries
end
