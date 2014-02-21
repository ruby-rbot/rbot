#-- vim:sw=2:et
#++
#
# :title: Unicode plugin
# To set the encoding of strings coming from the irc server.

class UnicodePlugin < CoreBotModule
  Config.register Config::BooleanValue.new('encoding.enable',
    :default => true,
    :desc => "Support for non-ascii charsets",
    :on_change => Proc.new { |bot, v| reconfigure_filter(bot) })

  Config.register Config::StringValue.new('encoding.charset',
    :default => 'utf-8',
    :desc => 'Server encoding.',
    :on_change => Proc.new { |bot, v| reconfigure_filter(bot) })

  class UnicodeFilter
    def initialize(charset)
      @charset = charset
    end

    def in(data)
      data.force_encoding @charset if data
      data.encode('UTF-16le', :invalid => :replace, :replace => '').encode('UTF-8')
    end

    def out(data)
      data
    end
  end


  def initialize(*a)
    super
    self.class.reconfigure_filter(@bot)
  end

  def cleanup
    debug "cleaning up encodings"
    @bot.socket.filter = nil
    super
  end

  def UnicodePlugin.reconfigure_filter(bot)
    debug "configuring encodings"
    charset = bot.config['encoding.charset']
    if bot.config['encoding.enable']
      bot.socket.filter = UnicodeFilter.new charset
    else
      bot.socket.filter = nil
    end
  end
end

UnicodePlugin.new
