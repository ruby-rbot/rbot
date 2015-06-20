#-- vim:sw=2:et
#++
#
# :title: irc logging into the journal
#
# Author:: Matthias Hecker (apoc@geekosphere.org)

class JournalIrcLogModule < CoreBotModule

  include Irc::Bot::Journal

  Config.register Config::ArrayValue.new('journal.irclog.whitelist',
    :default => [],
    :desc => 'only perform journal irc logging for those channel/users')

  Config.register Config::ArrayValue.new('journal.irclog.blacklist',
    :default => [],
    :desc => 'exclude journal irc logging for those channel/users')

  def irclog(payload)
    if payload[:target]
      target = payload[:target]
      whitelist = @bot.config['journal.irclog.whitelist']
      blacklist = @bot.config['journal.irclog.blacklist']
      unless whitelist.empty?
        return unless whitelist.include? target
      end
      unless blacklist.empty?
        return if blacklist.include? target
      end
    end
    @bot.journal.publish('irclog', payload)
  end

  # messages sent by the bot
  def sent(m)
    case m
    when NoticeMessage
      irclog type: 'notice', source: m.source, target: m.target, message: m.message, server: m.server
    when PrivMessage
      if m.ctcp
        irclog type: 'ctcp', source: m.source, target: m.target, ctcp: m.ctcp, message: m.message, server: m.server
      else
        irclog type: 'privmsg', source: m.source, target: m.target, message: m.message, server: m.server
      end
    when QuitMessage
      m.was_on.each { |ch|
        irclog type: 'quit', source: m.source, target: ch, message: m.message, server: m.server
      }
    end
  end

  # messages received from other clients
  def listen(m)
    case m
    when PrivMessage
      method = 'log_message'
    else
      method = 'log_' + m.class.name.downcase.match(/^irc::(\w+)message$/).captures.first
    end
    if self.respond_to?(method)
      self.__send__(method, m)
    else
      warning 'unhandled journal irc logging for ' + method
    end
  end

  def log_message(m)
    if m.ctcp
      irclog type: 'ctcp', source: m.source, target: m.target, ctcp: m.ctcp, message: m.message, server: m.server
    else
      irclog type: 'privmsg', source: m.source, target: m.target, message: m.message, server: m.server
    end
  end

  def log_notice(m)
    irclog type: 'notice', source: m.source, target: m.target, message: m.message, server: m.server
  end

  def motd(m)
    irclog type: 'motd', source: m.server, target: m.target, message: m.message, server: m.server
  end

  def log_nick(m)
    (m.is_on & @bot.myself.channels).each { |ch|
      irclog type: 'nick', old: m.oldnick, new: m.newnick, target: ch, server: m.server
    }
  end

  def log_quit(m)
    (m.was_on & @bot.myself.channels).each { |ch|
      irclog type: 'quit', source: m.source, target: ch, message: m.message, server: m.server
    }
  end

  def modechange(m)
    irclog type: 'mode', source: m.source, target: m.target, mode: m.message, server: m.server
  end

  def log_join(m)
    irclog type: 'join', source: m.source, target: m.channel, server: m.server
  end

  def log_part(m)
    irclog type: 'part', source: m.source, target: m.channel, message: m.message, server: m.server
  end

  def log_kick(m)
    irclog type: 'kick', source: m.source, target: m.channel, kicked: m.target, message: m.message, server: m.server
  end

  def log_invite(m)
    irclog type: 'invite', source: m.source, target: m.target, message: m.message, server: m.server
  end

  def log_topic(m)
    case m.info_or_set
    when :set
      irclog type: 'topic', source: m.source, target: m.channel, message: m.topic, server: m.server
    when :info
      topic = m.channel.topic
      irclog type: 'topic_info', source: topic.set_by, target: m.channel, set_on: topic.set_on, message: m.topic, server: m.server
    end
  end

end

plugin = JournalIrcLogModule.new
# make sure the logger gets loaded after the journal
plugin.priority = -1

