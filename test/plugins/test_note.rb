$:.unshift File.join(File.dirname(__FILE__), '..', '..', 'lib')
$:.unshift File.join(File.dirname(__FILE__), '..', '..')

require 'test/unit'
require 'test/mock'

require 'rbot/ircbot'
require 'rbot/registry'
require 'rbot/plugins'


class NotePluginTest < Test::Unit::TestCase
  def setup
    @bot = MockBot.new
    @bot.config['note.private_message'] = false
    manager = Irc::Bot::Plugins.manager
    manager.bot_associate(@bot)
    manager.load_botmodule_file('./data/rbot/plugins/note.rb')
    @plugin = manager.get_plugin('note')
  end

  def test_note
    assert_not_nil(@plugin)
    assert_equal(@plugin.help(nil), 'note <nick> <string> => stores a note (<string>) for <nick>')


    m = MockMessage.new
    @plugin.note(m, {nick: 'AlIcE', string: 'Hello Alice!'})
    assert_equal(1, m.replies.size)
    assert_equal('okay', m.replies.first)

    m = MockMessage.new('', 'Alice')
    @plugin.message(m)
    assert_equal(1, @bot.messages.size)
    to, message = @bot.messages.first
    assert_equal('Alice', to)
    assert_match(/you have notes!/, message)
    assert_match(/<user> Hello Alice!/, message)
  end
end
