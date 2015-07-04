$:.unshift File.join(File.dirname(__FILE__), '../lib')

require 'test/unit'
require 'rbot/ircbot'
require 'rbot/journal'
require 'rbot/journal/postgres.rb'
require 'rbot/journal/mongo.rb'

require 'benchmark'

DAY=60*60*24

class JournalMessageTest < Test::Unit::TestCase

  include Irc::Bot::Journal

  def test_get
    m = JournalMessage.create('foo', {'bar': 42, 'baz': nil, 'qux': {'quxx': 23}})
    assert_equal(42, m.get('bar'))
    assert_raise ArgumentError do
      m.get('nope')
    end
    assert_nil(m.get('nope', nil))
    assert_nil(m.get('baz'))
    assert_equal(23, m['qux.quxx'])
    assert_equal(nil, m['qux.nope'])
    assert_raise(ArgumentError) { m.get('qux.nope') }
  end

end

class QueryTest < Test::Unit::TestCase

  include Irc::Bot::Journal

  def test_define

    q = Query.define do
      id 'foo'
      id 'bar', 'baz'
      topic 'log.irc.*'
      topic 'log.core', 'baz'
      timestamp from: Time.now, to: Time.now + 60 * 10
      payload 'action': :privmsg, 'alice': 'bob'
      payload 'channel': '#rbot'
      payload 'foo.bar': 'baz'
    end
    assert_equal(['foo', 'bar', 'baz'], q.id)
    assert_equal(['log.irc.*', 'log.core', 'baz'], q.topic)
    assert_equal([:from, :to], q.timestamp.keys)
    assert_equal(Time, q.timestamp[:to].class)
    assert_equal(Time, q.timestamp[:from].class)
    assert_equal({
      'action': :privmsg, 'alice': 'bob',
      'channel': '#rbot',
      'foo.bar': 'baz'
    }, q.payload)

  end

  def test_topic_matches
    q = Query.define do
      topic 'foo'
    end
    assert_true(q.topic_matches?('foo'))
    assert_false(q.topic_matches?('bar'))
    assert_false(q.topic_matches?('foo.bar'))

    q = Query.define do
      topic 'foo.bar'
    end
    assert_false(q.topic_matches?('foo'))
    assert_false(q.topic_matches?('bar'))
    assert_true(q.topic_matches?('foo.bar'))

    q = Query.define do
      topic 'foo.*'
    end
    assert_false(q.topic_matches?('foo'))
    assert_false(q.topic_matches?('bar'))
    assert_true(q.topic_matches?('foo.bar'))
    assert_true(q.topic_matches?('foo.baz'))

    q = Query.define do
      topic '*.bar'
    end
    assert_false(q.topic_matches?('foo'))
    assert_false(q.topic_matches?('bar'))
    assert_true(q.topic_matches?('foo.bar'))
    assert_true(q.topic_matches?('bar.bar'))
    assert_false(q.topic_matches?('foo.foo'))

    q = Query.define do
      topic '*.*'
    end
    assert_false(q.topic_matches?('foo'))
    assert_true(q.topic_matches?('foo.bar'))

    q = Query.define do
      topic 'foo'
      topic 'bar'
      topic 'baz.alice.bob.*.foo'
    end
    assert_true(q.topic_matches?('foo'))
    assert_true(q.topic_matches?('bar'))
    assert_true(q.topic_matches?('baz.alice.bob.asdf.foo'))
    assert_false(q.topic_matches?('baz.alice.bob..foo'))

  end
  def test_matches
    q = Query.define do
      #id 'foo', 'bar'
      topic 'log.irc.*', 'log.core'
      timestamp from: Time.now - DAY, to: Time.now + DAY
      payload 'action': 'privmsg', 'foo.bar': 'baz'
    end
    assert_true(q.matches? JournalMessage.create('log.irc.raw', {'action' => 'privmsg'}))
    assert_false(q.matches? JournalMessage.create('baz', {}))
    assert_true(q.matches? JournalMessage.create('log.core', {foo: {bar: 'baz'}}))

    # tests timestamp from/to:
    assert_true(q.matches? JournalMessage.new(
      id: 'foo',
      topic: 'log.core',
      timestamp: Time.now,
      payload: {action: 'privmsg'}))
    assert_false(q.matches? JournalMessage.new(
      id: 'foo',
      topic: 'log.core',
      timestamp: Time.now - DAY*3,
      payload: {action: 'privmsg'}))
    assert_false(q.matches? JournalMessage.new(
      id: 'foo',
      topic: 'log.core',
      timestamp: Time.now + DAY*3,
      payload: {action: 'privmsg'}))
  end

end

class JournalBrokerTest < Test::Unit::TestCase

  include Irc::Bot::Journal

  def test_publish
    received = []
    journal = JournalBroker.new(consumer: Proc.new { |message|
      received << message
    })

    # publish some messages:
    journal.publish 'log.irc',
      source: 'alice', message: '<3 pg'
    journal.publish 'log.irc',
      source: 'bob', message: 'mysql > pg'
    journal.publish 'log.irc',
      source: 'alice', target: 'bob', action: :kick

    # wait for messages to be consumed:
    sleep 0.1
    assert_equal(3, received.length)
  end

  def test_subscribe
    received = []
    journal = JournalBroker.new

    # subscribe to messages for topic foo:
    sub = journal.subscribe('foo') do |message|
      received << message
    end

    # publish some messages:
    journal.publish 'foo', {}
    journal.publish 'bar', {}
    journal.publish 'foo', {}

    # wait for messages to be consumed:
    sleep 0.1
    assert_equal(2, received.length)

    received.clear

    journal.publish 'foo', {}
    sleep 0.1
    sub.cancel
    journal.publish 'foo', {}
    sleep 0.1
    assert_equal(1, received.length)
  end

end

module JournalStorageTestMixin

  include Irc::Bot::Journal

  def teardown
    @storage.drop
  end

  def test_operations
    # insertion
    m = JournalMessage.create('log.core', {foo: {bar: 'baz', qux: 42}})
    @storage.insert(m)

    # query by id
    res = @storage.find(Query.define { id m.id })
    assert_equal(1, res.length)
    assert_equal(m, res.first)

    # check timestamp was returned correctly:
    assert_equal(m.timestamp.strftime('%Y-%m-%d %H:%M:%S%z'),
                 res.first.timestamp.strftime('%Y-%m-%d %H:%M:%S%z'))

    # check if payload was returned correctly:
    assert_equal({'foo' => {'bar' => 'baz', 'qux' => 42}}, res.first.payload)

    # query by topic
    assert_equal(m, @storage.find(Query.define { topic('log.core') }).first)
    assert_equal(m, @storage.find(Query.define { topic('log.*') }).first)
    assert_equal(m, @storage.find(Query.define { topic('*.*') }).first)

    # query by timestamp range
    assert_equal(1, @storage.find(Query.define {
      timestamp(from: Time.now-DAY, to: Time.now+DAY) }).length)
    assert_equal(0, @storage.find(Query.define {
      timestamp(from: Time.now-DAY*2, to: Time.now-DAY) }).length)

    # query by payload
    res = @storage.find(Query.define { payload('foo.bar' => 'baz') })
    assert_equal(m, res.first)
    res = @storage.find(Query.define { payload('foo.bar' => 'x') })
    assert_true(res.empty?)

    # without arguments: find and count
    assert_equal(1, @storage.count)
    assert_equal(m, @storage.find.first)
  end

  def test_find
    # tests limit/offset and block parameters of find()
    @storage.insert(JournalMessage.create('irclogs', {message: 'foo'}))
    @storage.insert(JournalMessage.create('irclogs', {message: 'bar'}))
    @storage.insert(JournalMessage.create('irclogs', {message: 'baz'}))
    @storage.insert(JournalMessage.create('irclogs', {message: 'qux'}))

    msgs = []
    @storage.find(Query.define({topic: 'irclogs'}), 2, 1) do |m|
      msgs << m
    end
    assert_equal(2, msgs.length)
    assert_equal('bar', msgs.first['message'])
    assert_equal('baz', msgs.last['message'])

    msgs = []
    @storage.find(Query.define({topic: 'irclogs'})) do |m|
      msgs << m
    end
    assert_equal(4, msgs.length)
    assert_equal('foo', msgs.first['message'])
    assert_equal('qux', msgs.last['message'])

  end

  def test_operations_multiple
    # test operations on multiple messages
    # insert a bunch:
    @storage.insert(JournalMessage.create('test.topic', {name: 'one'}))
    @storage.insert(JournalMessage.create('test.topic', {name: 'two'}))
    @storage.insert(JournalMessage.create('test.topic', {name: 'three'}))
    @storage.insert(JournalMessage.create('archived.topic', {name: 'four'},
      timestamp: Time.now - DAY*100))
    @storage.insert(JournalMessage.create('complex', {name: 'five', country: {
      name: 'Italy'
    }}))
    @storage.insert(JournalMessage.create('complex', {name: 'six', country: {
      name: 'Austria'
    }}))

    # query by topic
    assert_equal(3, @storage.find(Query.define { topic 'test.*' }).length)
    # query by payload
    assert_equal(1, @storage.find(Query.define {
      payload('country.name' => 'Austria') }).length)
    # query by timestamp range
    assert_equal(1, @storage.find(Query.define {
      timestamp(from: Time.now - DAY*150, to: Time.now - DAY*50) }).length)

    # count with query
    assert_equal(2, @storage.count(Query.define { topic('complex') }))
    assert_equal(6, @storage.count)
    @storage.remove(Query.define { topic('archived.*') })
    assert_equal(5, @storage.count)
    @storage.remove
    assert_equal(0, @storage.count)
  end

  def test_broker_interface
    journal = JournalBroker.new(storage: @storage) 

    journal.publish 'irclogs', message: 'foo'
    journal.publish 'irclogs', message: 'bar'
    journal.publish 'irclogs', message: 'baz'
    journal.publish 'irclogs', message: 'qux'

    # wait for messages to be consumed:
    sleep 0.1

    msgs = []
    journal.find({topic: 'irclogs'}, 2, 1) do |m|
      msgs << m
    end
    assert_equal(2, msgs.length)
    assert_equal('bar', msgs.first['message'])
    assert_equal('baz', msgs.last['message'])

    journal.ensure_payload_index('foo.bar.baz')
  end

  NUM=100 # 1_000_000
  def test_benchmark
    puts

    assert_equal(0, @storage.count)
    # prepare messages to insert, we benchmark the storage backend not ruby
    num = 0
    messages = (0...NUM).map do
      num += 1
      JournalMessage.create(
            'test.topic.num_'+num.to_s, {answer: {number: '42', word: 'forty-two'}})
    end

    # iter is the number of operations performed WITHIN block
    def benchmark(label, iter, &block)
      time = Benchmark.realtime do
        yield
      end
      puts label + ' %d iterations, duration: %.3fms (%.3fms / iteration)' % [iter, time*1000, (time*1000) / iter]
    end

    benchmark(@storage.class.to_s+'~insert', messages.length) do
      messages.each { |m|
        @storage.insert(m)
      }
    end

    benchmark(@storage.class.to_s+'~find_by_id', messages.length) do
      messages.each { |m|
        @storage.find(Query.define { id m.id })
      }
    end
    benchmark(@storage.class.to_s+'~find_by_topic', messages.length) do
      messages.each { |m|
        @storage.find(Query.define { topic m.topic })
      }
    end
    benchmark(@storage.class.to_s+'~find_by_topic_wildcard', messages.length) do
      messages.each { |m|
        @storage.find(Query.define { topic m.topic.gsub('topic', '*') })
      }
    end
  end

end

if ENV['PG_URI']
class JournalStoragePostgresTest < Test::Unit::TestCase

  include JournalStorageTestMixin

  def setup
    @storage = Storage::PostgresStorage.new(
      uri: ENV['PG_URI'] || 'postgresql://localhost/rbot_journal',
      drop: true)
  end

  def test_query_to_sql
    q = Query.define do
      id 'foo'
      id 'bar', 'baz'
      topic 'log.irc.*'
      topic 'log.core', 'baz'
      timestamp from: Time.now, to: Time.now + 60 * 10
      payload 'action': :privmsg, 'alice': 'bob'
      payload 'channel': '#rbot'
      payload 'foo.bar': 'baz'
    end
    sql = @storage.query_to_sql(q)
    assert_equal("(id = $1 OR id = $2 OR id = $3) AND (topic ILIKE $4 OR topic ILIKE $5 OR topic ILIKE $6) AND (timestamp >= $7 AND timestamp <= $8) AND (payload->>'action' = $9 OR payload->>'alice' = $10 OR payload->>'channel' = $11 OR payload->'foo'->>'bar' = $12)", sql[0])
    q = Query.define do
      id 'foo'
    end
    assert_equal('(id = $1)', @storage.query_to_sql(q)[0])
    q = Query.define do
      topic 'foo.*.bar'
    end
    assert_equal('(topic ILIKE $1)', @storage.query_to_sql(q)[0])
    assert_equal(['foo.%.bar'], @storage.query_to_sql(q)[1])
  end

end
else
  puts 'NOTE: Set PG_URI environment variable to test postgresql storage.'
end

if ENV['MONGO_URI']
class JournalStorageMongoTest < Test::Unit::TestCase

  include JournalStorageTestMixin

  def setup
    @storage = Storage::MongoStorage.new(
      uri: ENV['MONGO_URI'] || 'mongodb://127.0.0.1:27017/rbot',
      drop: true)
  end
end
else
  puts 'NOTE: Set MONGO_URI environment variable to test postgresql storage.'
end

