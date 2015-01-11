# encoding: UTF-8
#-- vim:sw=2:et
#++
#
# :title: Mechanize Agent Factory
#
# Author:: Matthias Hecker <apoc@sixserv.org>
#
# Central factory for Mechanize agent instances, creates
# pre-configured agents. The main goal of this is to have
# central proxy and user agent configuration for mechanize.
#
# plugins can just call @bot.agent.create to return
# a new unique mechanize agent.

require 'mechanize'

require 'digest/md5'
require 'uri'

module ::Irc
module Utils

class AgentFactory
  Bot::Config.register Bot::Config::IntegerValue.new('agent.max_redir',
    :default => 5,
    :desc => "Maximum number of redirections to be used when getting a document")
  Bot::Config.register Bot::Config::BooleanValue.new('agent.ssl_verify',
    :default => true,
    :desc => "Whether or not you want to validate SSL certificates")
  Bot::Config.register Bot::Config::BooleanValue.new('agent.proxy_use',
    :default => true,
    :desc => "Use HTTP proxy or not")
  Bot::Config.register Bot::Config::StringValue.new('agent.proxy_host',
    :default => '127.0.0.1',
    :desc => "HTTP proxy hostname")
  Bot::Config.register Bot::Config::IntegerValue.new('agent.proxy_port',
    :default => 8118,
    :desc => "HTTP proxy port")
  Bot::Config.register Bot::Config::StringValue.new('agent.proxy_username',
    :default => nil,
    :desc => "HTTP proxy username")
  Bot::Config.register Bot::Config::StringValue.new('agent.proxy_password',
    :default => nil,
    :desc => "HTTP proxy password")

  def initialize(bot)
    @bot = bot
  end

  def cleanup
  end

  # Returns a new, unique instance of Mechanize.
  def create
    agent = Mechanize.new
    agent.redirection_limit = @bot.config['agent.max_redir']
    if not @bot.config['agent.ssl_verify']
      agent.agent.http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    if @bot.config['agent.proxy_use']
      agent.set_proxy(
        @bot.config['agent.proxy_host'],
        @bot.config['agent.proxy_port'],
        @bot.config['agent.proxy_username'],
        @bot.config['agent.proxy_password']
      )
    end
    agent
  end
end

end # Utils
end # Irc

class AgentPlugin < CoreBotModule
  def initialize(*a)
    super(*a)
    debug 'initializing agent factory'
    @bot.agent = Irc::Utils::AgentFactory.new(@bot)
  end

  def cleanup
    debug 'shutting down agent factory'
    @bot.agent.cleanup
    @bot.agent = nil
    super
  end
end

AgentPlugin.new

