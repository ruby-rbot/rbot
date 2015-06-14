# encoding: UTF-8
#-- vim:sw=2:et
#++
#
# :title: rbot's persistent message queue

require 'thread'
require 'securerandom'

module Irc
class Bot
module Journal

=begin rdoc

  The journal is a persistent message queue for rbot, its based on a basic
  publish/subscribe model and persists messages into backend databases
  that can be efficiently searched for past messages.

  It is a addition to the key value storage already present in rbot
  through its registry subsystem.

=end

  Config.register Config::StringValue.new('journal.storage',
    :default => nil,
    :requires_restart => true,
    :desc => 'storage engine used by the journal')
  Config.register Config::StringValue.new('journal.storage.uri',
    :default => nil,
    :requires_restart => true,
    :desc => 'storage database uri')

  class InvalidJournalMessage < StandardError
  end
  class ConsumeInterrupt < StandardError
  end
  class StorageError < StandardError
  end

  class JournalMessage
    # a unique identification of this message
    attr_reader :id

    # describes a hierarchical queue into which this message belongs
    attr_reader :topic

    # when this message was published as a Time instance
    attr_reader :timestamp

    # contains the actual message as a Hash
    attr_reader :payload

    def initialize(message)
      @id = message[:id]
      @timestamp = message[:timestamp]
      @topic = message[:topic]
      @payload = message[:payload]
      if @payload.class != Hash
        raise InvalidJournalMessage.new('payload must be a hash!')
      end
    end

    def get(pkey, default=:exception) # IDENTITY = Object.new instead of :ex..?
      value = pkey.split('.').reduce(@payload) do |hash, key|
        if hash.has_key?(key) or hash.has_key?(key.to_sym)
          hash[key] || hash[key.to_sym]
        else
          if default == :exception
            raise ArgumentError.new
          else
            default
          end
        end
      end
    end

    def ==(other)
      @id == other.id
    end

    def self.create(topic, payload, opt={})
      JournalMessage.new(
        id: opt[:id] || SecureRandom.uuid,
        timestamp: opt[:timestamp] || Time.now,
        topic: topic,
        payload: payload
      )
    end
  end

  module Storage
    class AbstractStorage
      # intializes/opens a new storage connection
      def initialize(opts={})
      end

      # inserts a message in storage
      def insert(message)
      end

      # creates/ensures a index exists on the payload specified by key
      def ensure_index(key)
      end

      # returns a array of message instances that match the query
      def find(query, limit=10, offset=0)
      end

      # returns the number of messages that match the query
      def count(query)
      end

      # delete messages that match the query
      def delete(query)
      end
    end
  end

  # Describes a query on journal entries, it is used both to describe
  # a subscription aswell as to query persisted messages.
  # There two ways to declare a Query instance, using
  # the DSL like this:
  #
  #   Query.define do
  #     id 'foo'
  #     id 'bar'
  #     topic 'log.irc.*'
  #     topic 'log.core'
  #     timestamp from: Time.now, to: Time.now + 60 * 10
  #     payload 'action': :privmsg
  #     payload 'channel': '#rbot'
  #     payload 'foo.bar': 'baz'
  #   end
  #
  # or using a hash: (NOTE: avoid using symbols in payload)
  #
  #   Query.define({
  #     id: ['foo', 'bar'],
  #     topic: ['log.irc.*', 'log.core'],
  #     timestamp: {
  #       from: Time.now
  #       to: Time.now + 60 * 10
  #     },
  #     payload: {
  #       'action' => 'privmsg'
  #       'channel' => '#rbot',
  #       'foo.bar' => 'baz'
  #     }
  #   })
  #
  class Query
    # array of ids to match (OR)
    attr_reader :id
    # array of topics to match with wildcard support (OR)
    attr_reader :topic
    # hash with from: timestamp and to: timestamp
    attr_reader :timestamp
    # hash of key values to match
    attr_reader :payload

    def initialize(query)
      @id = query[:id]
      @topic = query[:topic]
      @timestamp = query[:timestamp]
      @payload = query[:payload]
    end

    # returns true if the given message matches the query
    def matches?(message)
      return false if not @id.empty? and not @id.include? message.id
      return false if not @topic.empty? and not topic_matches? message.topic
      if @timestamp[:from]
        return false unless message.timestamp >= @timestamp[:from]
      end
      if @timestamp[:to]
        return false unless message.timestamp <= @timestamp[:to]
      end
      found = false
      @payload.each_pair do |key, value|
        begin
          message.get(key.to_s)
        rescue ArgumentError
        end
        found = true
      end
      return false if not found and not @payload.empty?
      true
    end

    def topic_matches?(_topic)
      @topic.each do |topic|
        if topic.include? '*'
          match = true
          topic.split('.').zip(_topic.split('.')).each do |a, b|
            if a == '*'
              if not b or b.empty?
                match = false
              end
            else
              match = false unless a == b
            end
          end
          return true if match
        else
          return true if topic == _topic
        end
      end
      return false
    end

    # factory that constructs a query
    class Factory
      attr_reader :query
      def initialize
        @query = {
          id: [],
          topic: [],
          timestamp: {
            from: nil, to: nil
          },
          payload: {}
        }
      end

      def id(*_id)
        @query[:id] += _id
      end

      def topic(*_topic)
          @query[:topic] += _topic
      end

      def timestamp(range)
        @query[:timestamp] = range
      end

      def payload(query)
        @query[:payload].merge!(query)
      end
    end

    def self.define(query=nil, &block)
      factory = Factory.new
      if block_given?
        factory.instance_eval(&block)
        query = factory.query
      end
      Query.new query
    end

  end


  class JournalBroker
    class Subscription
      attr_reader :query
      attr_reader :block
      def initialize(broker, query, block)
        @broker = broker
        @query = query
        @block = block
      end
      def cancel
        @broker.unsubscribe(self)
      end
    end

    def initialize(opts={})
      # overrides the internal consumer with a block
      @consumer = opts[:consumer]
      # storage backend
      @storage = opts[:storage]
      @queue = Queue.new
      # consumer thread:
      @thread = Thread.new do
        loop do
          begin
            consume @queue.pop
          # pop(true) ... rescue ThreadError => e
          rescue ConsumeInterrupt => e
            error 'journal broker: stop thread, consume interrupt raised'
            break
          rescue Exception => e
            error 'journal broker: exception in consumer thread'
            error $!
          end
        end
      end
      # TODO: this is a first naive implementation, later we do the
      #       message/query matching for incoming messages more efficiently
      @subscriptions = []
    end

    def consume(message)
      return unless message
      @consumer.call(message) if @consumer

      # notify subscribers
      @subscriptions.each do |s|
        if s.query.matches? message
          s.block.call(message)
        end
      end

      @storage.insert(message) if @storage
    end

    def persists?
      true if @storage
    end

    def join
      @thread.join
    end

    def shutdown
      @thread.raise ConsumeInterrupt.new
    end

    def publish(topic, payload)
      @queue.push JournalMessage::create(topic, payload)
    end

    # subscribe to messages that match the given query
    def subscribe(query, &block)
      raise ArgumentError.new unless block_given?
      s = Subscription.new(self, query, block)
      @subscriptions << s
      s
    end

    def unsubscribe(subscription)
      @subscriptions.delete subscription
    end

  end

end # Journal
end # Bot
end # Irc

