$:.unshift File.join(File.dirname(__FILE__), '../lib')

require 'test/unit'
require 'rbot/ircbot'
require 'rbot/journal'

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

  DAY=60*60*24
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

