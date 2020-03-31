$:.unshift File.join(File.dirname(__FILE__), '../lib')

module Irc
class Bot
  module Config
    @@datadir = File.expand_path(File.dirname($0) + '/../data/rbot')
    @@coredir = File.expand_path(File.dirname($0) + '/../lib/rbot/core')
  end
end
end

require 'test/unit'
require 'rbot/ircbot'
require 'rbot/registry'
require 'rbot/plugins'


class MockBot
  attr_reader :filters
  def initialize
    @filters = {}
  end

  def register_filter(name, &block)
    @filters[name] = block
  end

  def path
    ''
  end

  def registry_factory
    Irc::Bot::Registry.new('tc')
  end
end


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
  end
end
