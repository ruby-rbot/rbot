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
    Irc::Bot::Plugins.manager.bot_associate(MockBot.new)

    # @plugin = RotPlugin.new(MockBot.new)
    # require ''
    plugin_module = Module.new
    fname = './data/rbot/plugins/rot13.rb'
    bindtextdomain_to(plugin_module, "rbot-#{File.basename(fname, '.rb')}")
    plugin_string = IO.read(fname)
    plugin_module.module_eval(plugin_string, fname)
  end

  def test_rot13
    plugins = Irc::Bot::Plugins.manager.botmodules[:Plugin]
    assert_equal(plugins.size, 1)
    rot13 = plugins.first

    assert_equal(rot13.help(nil), "rot13 <string> => encode <string> to rot13 or back")
  end
end
