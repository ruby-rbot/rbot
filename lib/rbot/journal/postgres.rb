# encoding: UTF-8
#-- vim:sw=2:et
#++
#
# :title: journal backend for postgresql

require 'pg'
require 'json'

# wraps the postgres driver in a single thread
class PGWrapper
  def initialize(uri)
    @uri = uri
    @queue = Queue.new
    run_thread
  end

  def run_thread
    Thread.new do
      @conn = PG.connect(@uri)
      while message = @queue.pop
        return_queue = message.shift
        begin
          result = @conn.send(*message)
          return_queue << [:result, result]
        rescue Exception => e
          return_queue << [:exception, e]
        end
      end
      @conn.finish
    end
  end

  def run_in_thread(*args)
    rq = Queue.new
    @queue << [rq, *args]
    type, result = rq.pop
    if type == :exception
      raise result
    else
      result
    end
  end

  public

  def destroy
    @queue << nil
  end

  def exec(query)
    run_in_thread(:exec, query)
  end

  def exec_params(query, params)
    run_in_thread(:exec_params, query, params)
  end

  def escape_string(string)
    @conn.escape_string(string)
  end
end

# as a replacement for CREATE INDEX IF NOT EXIST that is not in postgres.
# define function to be able to create an index in case it doesnt exist:
# source: http://stackoverflow.com/a/26012880
CREATE_INDEX = <<-EOT
CREATE OR REPLACE FUNCTION create_index(table_name text, index_name text, column_name text) RETURNS void AS $$ 
declare 
   l_count integer;
begin
  select count(*)
     into l_count
  from pg_indexes
  where schemaname = 'public'
    and tablename = lower(table_name)
    and indexname = lower(index_name);

  if l_count = 0 then 
     execute 'create index ' || index_name || ' on ' || table_name || '(' || column_name || ')';
  end if;
end;
$$ LANGUAGE plpgsql;
EOT

module Irc
class Bot
module Journal

  module Storage

    class PostgresStorage < AbstractStorage
      attr_reader :conn

      def initialize(opts={})
        @uri = opts[:uri] || 'postgresql://localhost/rbot'
        @conn = PGWrapper.new(@uri)
        @conn.exec('set client_min_messages = warning')
        @conn.exec(CREATE_INDEX)
        @version = @conn.exec('SHOW server_version;')[0]['server_version']

        @version.gsub!(/^(\d+\.\d+)$/, '\1.0')
        log 'journal storage: postgresql connected to version: ' + @version
        
        version = @version.split('.')[0,3].join.to_i
        if version < 930
          raise StorageError.new(
            'PostgreSQL Version too old: %s, supported: >= 9.3' % [@version])
        end
        @jsonb = (version >= 940)
        log 'journal storage: no jsonb support, consider upgrading postgres' unless @jsonb
        log 'journal storage: postgres backend is using JSONB :)' if @jsonb

        drop if opts[:drop]
        create_table
        create_index('topic_index', 'topic')
        create_index('timestamp_index', 'timestamp')
      end

      def create_table
        @conn.exec('
          CREATE TABLE IF NOT EXISTS journal
            (id UUID PRIMARY KEY,
             topic TEXT NOT NULL,
             timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
             payload %s NOT NULL)' % [@jsonb ? 'JSONB' : 'JSON'])
      end

      def create_index(index_name, column_name)
        debug 'journal postges backend: create index %s for %s' % [
          index_name, column_name]
        @conn.exec_params('SELECT create_index($1, $2, $3)', [
          'journal', index_name, column_name])
      end

      def create_payload_index(key)
        index_name = 'idx_payload_' + key.gsub('.', '_')
        column = sql_payload_selector(key)
        create_index(index_name, column)
      end

      def ensure_index(key)
        create_payload_index(key)
      end

      def insert(m)
        @conn.exec_params('INSERT INTO journal VALUES ($1, $2, $3, $4);',
          [m.id, m.topic, m.timestamp, JSON.generate(m.payload)])
      end

      def find(query=nil, limit=100, offset=0, &block)
        def to_message(row)
          timestamp = DateTime.strptime(row['timestamp'], '%Y-%m-%d %H:%M:%S%z')
          JournalMessage.new(id: row['id'], timestamp: timestamp,
            topic: row['topic'], payload: JSON.parse(row['payload']))
        end

        if query
          sql, params = query_to_sql(query)
          sql = 'SELECT * FROM journal WHERE ' + sql + ' LIMIT %d OFFSET %d' % [limit.to_i, offset.to_i]
        else
          sql = 'SELECT * FROM journal LIMIT %d OFFSET %d' % [limit.to_i, offset.to_i]
          params = []
        end
        res = @conn.exec_params(sql, params)
        if block_given?
          res.each { |row| block.call(to_message(row)) }
        else
          res.map { |row| to_message(row) }
        end
      end

      # returns the number of messages that match the query
      def count(query=nil)
        if query
          sql, params = query_to_sql(query)
          sql = 'SELECT COUNT(*) FROM journal WHERE ' + sql
        else
          sql = 'SELECT COUNT(*) FROM journal'
          params = []
        end
        res = @conn.exec_params(sql, params)
        res[0]['count'].to_i
      end

      def remove(query=nil)
        if query
          sql, params = query_to_sql(query)
          sql = 'DELETE FROM journal WHERE ' + sql
        else
          sql = 'DELETE FROM journal;'
          params = []
        end
        res = @conn.exec_params(sql, params)
      end

      def drop
        @conn.exec('DROP TABLE journal;') rescue nil
      end

      def sql_payload_selector(key)
        selector = 'payload'
        k = key.to_s.split('.')
        k.each_index { |i|
          if i >= k.length-1
            selector += '->>\'%s\'' % [@conn.escape_string(k[i])]
          else
            selector += '->\'%s\'' % [@conn.escape_string(k[i])]
          end
        }
        selector
      end

      def query_to_sql(query)
        params = []
        placeholder = Proc.new do |value|
          params << value
          '$%d' % [params.length]
        end
        sql = {op: 'AND', list: []}

        # ID query OR condition
        unless query.id.empty?
          sql[:list] << {
            op: 'OR',
            list: query.id.map { |id| 
              'id = ' + placeholder.call(id)
            }
          }
        end

        # Topic query OR condition
        unless query.topic.empty?
          sql[:list] << {
            op: 'OR',
            list: query.topic.map { |topic| 
              'topic ILIKE ' + placeholder.call(topic.gsub('*', '%'))
            }
          }
        end

        # Timestamp range query AND condition
        if query.timestamp[:from] or query.timestamp[:to]
          list = []
          if query.timestamp[:from]
            list << 'timestamp >= ' + placeholder.call(query.timestamp[:from])
          end
          if query.timestamp[:to]
            list << 'timestamp <= ' + placeholder.call(query.timestamp[:to])
          end
          sql[:list] << {
            op: 'AND',
            list: list
          }
        end

        # Payload query
        unless query.payload.empty?
          list = []
          query.payload.each_pair do |key, value|
            selector = sql_payload_selector(key)
            list << selector + ' = ' + placeholder.call(value)
          end
          sql[:list] << {
            op: 'OR',
            list: list
          }
        end

        sql = sql[:list].map { |stmt|
          '(' + stmt[:list].join(' %s ' % [stmt[:op]]) + ')'
        }.join(' %s ' % [sql[:op]])

        [sql, params]
      end
    end
  end
end # Journal
end # Bot
end # Irc
