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
  end
end
