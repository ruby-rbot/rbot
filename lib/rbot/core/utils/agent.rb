# encoding: UTF-8
#-- vim:sw=2:et
#++
#
# :title: Mechanize Agent Factory
#
# Author:: Matthias Hecker <apoc@sixserv.org>
#
# Central repository for Mechanize agent instances, creates
# pre-configured agents, allows for persistent caching,
# cookie and page serialization.

require 'mechanize'

module ::Irc
module Utils

class AgentFactory
  Bot::Config.register Bot::Config::IntegerValue.new('agent.max_redir',
    :default => 5,
    :desc => "Maximum number of redirections to be used when getting a document")

  def initialize(bot)
    @bot = bot
  end

  def cleanup
  end

  # Returns a new, unique instance of Mechanize.
  def get_instance
    agent = Mechanize.new
    agent.redirection_limit = @bot.config['agent.max_redir']

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

