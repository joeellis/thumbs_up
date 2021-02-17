require 'simplecov'
require 'minitest/autorun'
SimpleCov.start

$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'active_record'

config = {
  :database => 'thumbs_up_test',
  :username => 'test'
}

case ENV['DB']
  when 'mysql'
    config = {
      :adapter => 'mysql2',
      :database => 'thumbs_up_test',
      :username => 'test',
      :password => 'test',
      :socket => '/tmp/mysql.sock'
    }
    if ENV['TRAVIS']
      config = {
        :adapter => 'mysql2',
        :database => 'thumbs_up_test',
        :username => 'root'
      }
    end
    ActiveRecord::Base.establish_connection(config)
    ActiveRecord::Base.connection.drop_database(config[:database]) rescue nil
    ActiveRecord::Base.connection.create_database(config[:database])
  when 'postgres'
    config = {
      :adapter => 'postgresql',
      :database => 'thumbs_up_test',
      :username => 'test',
    }
    if ENV['TRAVIS']
      config = {
        :adapter => 'postgresql',
        :database => 'thumbs_up_test',
        :username => 'postgres',
      }
    end
    ActiveRecord::Base.establish_connection(config.merge({ :database => 'postgres' }))
    ActiveRecord::Base.connection.drop_database(config[:database])
    ActiveRecord::Base.connection.create_database(config[:database])
  when 'sqlite3'
    config = {
      :adapter => 'sqlite3',
      :database => 'test.sqlite3',
      :username => 'test',
    }
end

ActiveRecord::Base.establish_connection(config)

ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :votes, :force => true do |t|
    t.boolean    :vote,     :default => false
    t.references :voteable, :polymorphic => true, :null => false
    t.references :voter,    :polymorphic => true
    t.timestamps :null => false
  end

  add_index :votes, [:voter_id, :voter_type]
  add_index :votes, [:voteable_id, :voteable_type]

  # Comment out the line below to allow multiple votes per voter on a single entity.
  add_index :votes, [:voter_id, :voter_type, :voteable_id, :voteable_type], :unique => true, :name => 'fk_one_vote_per_user_per_entity'

  create_table :users, :force => true do |t|
    t.string :name
    t.timestamps :null => false
  end

  create_table :items, :force => true do |t|
    t.integer :user_id
    t.string  :name
    t.string  :description
  end

  create_table :other_items, :force => true do |t|
    t.integer :user_id
    t.string  :name
    t.string  :description
  end

  create_table :user_customs, :force => true do |t|
    t.string :name
    t.timestamps :null => false
  end

  create_table :item_customs, :force => true do |t|
    t.integer :user_id
    t.string  :name
    t.string  :description
  end

  create_table :other_item_customs, :force => true do |t|
    t.integer :user_id
    t.string  :name
    t.string  :description
  end

end

require 'thumbs_up'

class Vote < ActiveRecord::Base

  scope :for_voter, lambda { |*args| where(["voter_id = ? AND voter_type = ?", args.first.id, args.first.class.name]) }
  scope :for_voteable, lambda { |*args| where(["voteable_id = ? AND voteable_type = ?", args.first.id, args.first.class.name]) }
  scope :recent, lambda { |*args| where(["created_at > ?", (args.first || 2.weeks.ago)]) }
  scope :descending, lambda { order("created_at DESC") }

  belongs_to :voteable, :polymorphic => true
  belongs_to :voter, :polymorphic => true

  attr_accessible :vote, :voter, :voteable if ActiveRecord::VERSION::MAJOR < 4

  # Comment out the line below to allow multiple votes per user.
  validates_uniqueness_of :voteable_id, :scope => [:voteable_type, :voter_type, :voter_id]
end

class Item < ActiveRecord::Base
  # This is default, however because the setting is app-wide, and changed elsewhere, we need to be explicit
  ThumbsUp.configuration.voteable_relationship_name = :votes
  ThumbsUp.configuration.voter_relationship_name = :votes
  acts_as_voteable
  belongs_to :user
end

class OtherItem < ActiveRecord::Base
  # This is default, however because the setting is app-wide, and changed elsewhere, we need to be explicit
  ThumbsUp.configuration.voteable_relationship_name = :votes
  ThumbsUp.configuration.voter_relationship_name = :votes
  acts_as_voteable
  belongs_to :user
end

class User < ActiveRecord::Base
  # This is default, however because the setting is app-wide, and changed elsewhere, we need to be explicit
  ThumbsUp.configuration.voteable_relationship_name = :votes
  ThumbsUp.configuration.voter_relationship_name = :votes
  acts_as_voter
  has_many :items
  has_karma :items

  def self.default_karma
    self.karmic_objects = nil
    has_karma :items, :weight => 1
  end

  def self.weighted_has_karma
    self.karmic_objects = nil
    has_karma :items, :weight => [ 10, 15 ]
  end

  def self.upvote_only_has_karma
    self.karmic_objects = nil
    has_karma :items, :weight => 1.3
  end
end

class ItemCustom < ActiveRecord::Base
  ThumbsUp.configuration.voteable_relationship_name = :votes_on
  ThumbsUp.configuration.voter_relationship_name = :votes_by
  acts_as_voteable
  belongs_to :user
end

class OtherItemCustom < ActiveRecord::Base
  ThumbsUp.configuration.voteable_relationship_name = :votes_on
  ThumbsUp.configuration.voter_relationship_name = :votes_by
  acts_as_voteable
  belongs_to :user
end

class UserCustom < ActiveRecord::Base
  ThumbsUp.configuration.voteable_relationship_name = :votes_on
  ThumbsUp.configuration.voter_relationship_name = :votes_by
  acts_as_voter
  has_many :items
  has_karma :items
end
