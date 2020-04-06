$:.unshift File.join(File.dirname(__FILE__), '..', '..', 'lib')
$:.unshift File.join(File.dirname(__FILE__), '..', '..')

require 'test/unit'
require 'test/mock'

require 'rbot/ircbot'
require 'rbot/registry'
require 'rbot/plugins'
require 'rbot/language'

class PointsPluginTest < Test::Unit::TestCase
  def setup
    manager = Irc::Bot::Plugins.manager
    manager.bot_associate(MockBot.new)
    manager.load_botmodule_file('./data/rbot/plugins/points.rb')
    @plugin = manager.get_plugin('points')
  end

  def test_points
    assert_not_nil(@plugin)
    assert_not_empty(@plugin.help(nil))

    m = MockMessage.new('', 'user')
    @plugin.points(m, key: 'linux')
    assert_equal('linux has zero points', m.replies.first)

    m = MockMessage.new('linux++', 'user')
    @plugin.message(m)
    assert_equal('linux now has 1 points!', m.replies.first)

    m = MockMessage.new('linux++', 'user')
    @plugin.message(m)
    assert_equal('linux now has 2 points!', m.replies.first)

    m = MockMessage.new('linux++', 'linux')
    @plugin.message(m)
    assert_empty(m.replies)

    m = MockMessage.new('', 'user')
    @plugin.points(m, key: 'linux')
    assert_equal('points for linux: 2', m.replies.first)

    m = MockMessage.new('', 'linux')
    @plugin.points(m, {})
    assert_equal('points for linux: 2', m.replies.first)

    m = MockMessage.new('alice++', 'user')
    @plugin.message(m)
    assert_equal('alice now has 1 points!', m.replies.first)

    ignored = [
      '++alice',
      '--alice',
      'something something --github',
      'ls --sort time',
      '-- foo',
      '++ foo',
    ]
    ignored.each do |ignore|
      m = MockMessage.new(ignore, 'user')
      @plugin.message(m)
      assert_empty(m.replies, "message should've been ignored: #{ignore.inspect}")
    end

    m = MockMessage.new('bob++', 'user')
    @plugin.message(m)
    assert_equal('bob now has 1 points!', m.replies.first)

    m = MockMessage.new('bot++', 'user')
    @plugin.message(m)
    assert_include(MockBot.new.lang.strings['thanks'], m.replies.first)
  end
end
