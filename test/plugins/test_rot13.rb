$:.unshift File.join(File.dirname(__FILE__), '..', '..', 'lib')
$:.unshift File.join(File.dirname(__FILE__), '..', '..')

require 'test/unit'
require 'test/mock'

require 'rbot/ircbot'
require 'rbot/registry'
require 'rbot/plugins'


class PluginTest < Test::Unit::TestCase
  def setup
    manager = Irc::Bot::Plugins.manager
    manager.bot_associate(MockBot.new)
    manager.load_botmodule_file('./data/rbot/plugins/rot13.rb')
    @plugin = manager.get_plugin('rot')
  end

  def test_rot13
    assert_not_nil(@plugin)
    assert_equal(@plugin.help(nil), "rot13 <string> => encode <string> to rot13 or back")
    m = MockMessage.new
    @plugin.rot13(m, {string: 'Hello World'})
    assert_equal(m.replies.first, 'Uryyb Jbeyq')
  end
end
