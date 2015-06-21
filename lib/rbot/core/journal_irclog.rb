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

  def publish(payload)
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

  def log_message(m)
    unless m.kind_of? BasicUserMessage
      warning 'journal irc logger can\'t log %s message' % [m.class.to_s]
    else
      payload = {
        type: m.class.name.downcase.match(/(\w+)message/).captures.first,
        addressed: m.address?,
        replied: m.replied?,
        identified: m.identified?,

        source: m.source.to_s,
        source_user: m.botuser.to_s,
        source_address: m.sourceaddress,
        target: m.target.to_s,
        server: m.server.to_s,

        message: m.logmessage,
      }
      publish(payload)
    end
  end

  # messages sent
  def sent(m)
    log_message(m)
  end

  # messages received
  def listen(m)
    log_message(m)
  end
end

plugin = JournalIrcLogModule.new
# make sure the logger gets loaded after the journal
plugin.priority = -1

