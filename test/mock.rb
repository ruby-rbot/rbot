$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')
$:.unshift File.join(File.dirname(__FILE__), '..')
#require 'rbot/logger'
#Irc::Bot::LoggerManager.instance.set_level(5)

module Irc
class Bot
  module Config
    @@datadir = File.expand_path(File.dirname(__FILE__) + '/../data/rbot')
    @@coredir = File.expand_path(File.dirname(__FILE__) + '/../lib/rbot/core')
  end
end
end


class MockBot
  attr_reader :filters, :lang

  def initialize
    @filters = {}
    @lang = Irc::Bot::Language.new(self, 'english')
  end

  def register_filter(name, &block)
    @filters[name] = block
  end

  def filter(name, value)
    @filters[name].call({text: value})[:text]
  end

  def nick
    'bot'
  end

  def path(*components)
    File.join('/tmp/rbot-test', *(components.map {|c| c.to_s}))
  end

  def plugins
    nil
  end

  def registry_factory
    Irc::Bot::Registry.new('mem')
  end
end


class MockMessage
  attr_reader :message
  attr_reader :replies
  attr_reader :channel
  attr_reader :sourcenick

  def initialize(message='', source='user')
    @message = message
    @sourcenick = source
    @channel = Irc::Channel.new('#test', '', ['bob'], server: nil)
    @replies = []
  end

  def reply(message)
    @replies << message
  end

  def public?
    true
  end
end


