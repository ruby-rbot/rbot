# encoding: UTF-8
#-- vim:sw=2:et
#++
#
# :title: journal backend for mongoDB

require 'mongo'
require 'json'

module Irc
class Bot
module Journal

  module Storage

    class MongoStorage < AbstractStorage
      attr_reader :client

      def initialize(opts={})
        Mongo::Logger.logger.level = Logger::WARN
        @uri = opts[:uri] || 'mongodb://127.0.0.1:27017/rbot'
        @client = Mongo::Client.new(@uri)
        @collection = @client['journal']
        log 'journal storage: mongodb connected to ' + @uri
        
        drop if opts[:drop]
        @collection.indexes.create_one({topic: 1})
        @collection.indexes.create_one({timestamp: 1})
      end

      def ensure_payload_index(key)
        @collection.indexes.create_one({'payload.'+key => 1})
      end

      def insert(m)
        @collection.insert_one({
          '_id' => m.id,
          'topic' => m.topic,
          'timestamp' => m.timestamp,
          'payload' => m.payload
        })
      end

      def find(query=nil, limit=100, offset=0, &block)
        def to_message(document)
          JournalMessage.new(id: document['_id'],
                             timestamp: document['timestamp'].localtime,
                             topic: document['topic'],
                             payload: document['payload'].to_h)
        end

        cursor = query_cursor(query).skip(offset).limit(limit)

        if block_given?
          cursor.each { |document| block.call(to_message(document)) }
        else
          cursor.map { |document| to_message(document) }
        end
      end

      # returns the number of messages that match the query
      def count(query=nil)
        query_cursor(query).count
      end

      def remove(query=nil)
        query_cursor(query).delete_many
      end

      def drop
        @collection.drop
      end

      def query_cursor(query)
        unless query
          return @collection.find()
        end

        query_and = []

        # ID query OR condition
        unless query.id.empty?
          query_and << {
            '$or' => query.id.map { |_id| 
              {'_id' => _id}
            }
          }
        end

        unless query.topic.empty?
          query_and << {
            '$or' => query.topic.map { |topic|
              if topic.include?('*')
                pattern = topic.gsub('.', '\.').gsub('*', '.*')
                {'topic' => {'$regex' => pattern}}
              else
                {'topic' => topic}
              end
            }
          }
        end

        if query.timestamp[:from] or query.timestamp[:to]
          where = {}
          if query.timestamp[:from]
            where['$gte'] = query.timestamp[:from]
          end
          if query.timestamp[:to]
            where['$lte'] = query.timestamp[:to]
          end
          query_and << {'timestamp' => where}
        end

        unless query.payload.empty?
          query_and << {
            '$or' => query.payload.map { |key, value|
              key = 'payload.' + key
              {key => value}
            }
          }
        end

        @collection.find({
          '$and' => query_and
        })
      end
    end
  end
end # Journal
end # Bot
end # Irc
