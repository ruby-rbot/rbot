# encoding: UTF-8
#-- vim:sw=2:et
#++
#
# :title: rbot's persistent message queue
#
# Author:: Matthias Hecker (apoc@geekosphere.org)

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

  class InvalidJournalMessage < StandardError
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

    # Access payload value by key.
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

    # Access payload value by key alias for get(key, nil).
    def [](key)
      get(key, nil)
    end

    def ==(other)
      (@id == other.id) rescue false
    end

    def self.create(topic, payload, opt={})
      # cleanup payload to only contain strings
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
      def ensure_payload_index(key)
      end

      # returns a array of message instances that match the query
      def find(query=nil, limit=100, offset=0, &block)
      end

      # returns the number of messages that match the query
      def count(query=nil)
      end

      # remove messages that match the query
      def remove(query=nil)
      end

      # destroy the underlying table/collection
      def drop
      end

      # Returns all classes from the namespace that implement this interface
      def self.get_impl
        ObjectSpace.each_object(Class).select { |klass| klass < self }
      end
    end

    def self.create(name, uri)
      log 'load journal storage adapter: ' + name
      load File.join(File.dirname(__FILE__), 'journal', name + '.rb')
      cls = AbstractStorage.get_impl.first
      cls.new(uri: uri)
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
      @id = query[:id] || []
      @id = [@id] if @id.is_a? String
      @topic = query[:topic] || []
      @topic = [@topic] if @topic.is_a? String
      @timestamp = {
        from: nil, to: nil
      }
      if query[:timestamp] and query[:timestamp][:from]
        @timestamp[:from] = query[:timestamp][:from]
      end
      if query[:timestamp] and query[:timestamp][:to]
        @timestamp[:to] = query[:timestamp][:to]
      end
      @payload = query[:payload] || {}
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
    attr_reader :storage
    class Subscription
      attr_reader :topic
      attr_reader :block
      def initialize(broker, topic, block)
        @broker = broker
        @topic = topic
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
      unless @storage
        warning 'journal broker: no storage set up, won\'t persist messages'
      end
      @queue = Queue.new
      # consumer thread:
      @thread = Thread.new do
        while message = @queue.pop
          begin
            consume message
          # pop(true) ... rescue ThreadError => e
          rescue Exception => e
            error 'journal broker: exception in consumer thread'
            error $!
          end
        end
      end
      @subscriptions = []
      # lookup-table for subscriptions by their topic
      @topic_subs = {}
    end

    def consume(message)
      return unless message
      @consumer.call(message) if @consumer

      # notify subscribers
      if @topic_subs.has_key? message.topic
        @topic_subs[message.topic].each do |s|
          s.block.call(message)
        end
      end

      @storage.insert(message) if @storage
    end

    def persists?
      true if @storage
    end

    def shutdown
      log 'journal shutdown'
      @subscriptions.clear
      @topic_subs.clear
      @queue << nil
      @thread.join
      @thread = nil
    end

    def publish(topic, payload)
      debug 'journal publish message in %s: %s' % [topic, payload.inspect]
      @queue << JournalMessage::create(topic, payload)
      nil
    end

    # Subscribe to receive messages from a topic.
    #
    # You can use this method to subscribe to messages that
    # are published within a specified topic. You must provide
    # a receiving block to receive messages one-by-one.
    # The method returns an instance of Subscription that can
    # be used to cancel the subscription by invoking cancel
    # on it.
    #
    #   journal.subscribe('irclog') do |message|
    #     # received irclog messages...
    #   end
    #
    def subscribe(topic=nil, &block)
      raise ArgumentError.new unless block_given?
      s = Subscription.new(self, topic, block)
      @subscriptions << s
      unless @topic_subs.has_key? topic
        @topic_subs[topic] = []
      end
      @topic_subs[topic] << s
      s
    end

    def unsubscribe(s)
      if @topic_subs.has_key? s.topic
        @topic_subs[s.topic].delete(s)
      end
      @subscriptions.delete s
    end

    # Find and return persisted messages by a query.
    #
    # This method will either return all messages or call the provided
    # block for each message. It will filter the messages by the
    # provided Query instance. Limit and offset might be used to
    # constrain the result.
    # The query might also be a hash or proc that is passed to
    # Query.define first.
    #
    # @param query [Query] 
    # @param limit [Integer] how many items to return
    # @param offset [Integer] relative offset in results
    def find(query, limit=100, offset=0, &block)
      unless query.is_a? Query
        query = Query.define(query)
      end
      if block_given?
        @storage.find(query, limit, offset, &block)
      else
        @storage.find(query, limit, offset)
      end
    end

    def count(query=nil)
      unless query.is_a? Query
        query = Query.define(query)
      end
      @storage.count(query)
    end

    def remove(query=nil)
      unless query.is_a? Query
        query = Query.define(query)
      end
      @storage.remove(query)
    end

    def ensure_payload_index(key)
      @storage.ensure_payload_index(key)
    end

  end

end # Journal
end # Bot
end # Irc

