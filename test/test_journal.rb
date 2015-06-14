$:.unshift File.join(File.dirname(__FILE__), '../lib')

require 'test/unit'
require 'rbot/ircbot'
require 'rbot/journal'
require 'rbot/journal/postgres.rb'

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
    assert_equal(23, m.get('qux.quxx'))
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

    # subscribe to messages:
    sub = journal.subscribe(Query.define { topic 'foo' }) do |message|
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

class JournalStoragePostgresTest < Test::Unit::TestCase

  include Irc::Bot::Journal

  def setup
    @storage = Storage::PostgresStorage.new(
      uri: ENV['DB_URI'] || 'postgresql://localhost/rbot_journal',
      drop: true)
  end

  def teardown
    @storage.drop
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

  def test_operations
    # insertion
    m = JournalMessage.create('log.core', {foo: {bar: 'baz'}})
    @storage.insert(m)

    # query by id
    res = @storage.find(Query.define { id m.id })
    assert_equal(1, res.length)
    assert_equal(m, res.first)

    # check timestamp was returned correctly:
    assert_equal(m.timestamp.strftime('%Y-%m-%d %H:%M:%S%z'),
                 res.first.timestamp.strftime('%Y-%m-%d %H:%M:%S%z'))

    # check if payload was returned correctly:
    assert_equal({'foo' => {'bar' => 'baz'}}, res.first.payload)

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


  end

  def test_journal
    received = []
    # this journal persists messages in the test storage:
    journal = JournalBroker.new(storage: @storage)


  end

end

