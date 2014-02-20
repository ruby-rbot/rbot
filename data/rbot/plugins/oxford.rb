# encoding: UTF-8
#-- vim:sw=2:et
#++
#
# :title: Oxford Dictionary lookup plugin for rbot
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2006-2007 Giuseppe Bilotta
# License:: GPL v2
#

class OxfordPlugin < Plugin
  Config.register Config::IntegerValue.new('oxford.hits',
    :default => 3,
    :desc => "Number of hits to return from a dictionary lookup")
  Config.register Config::IntegerValue.new('oxford.first_par',
    :default => 0,
    :desc => "When set to n > 0, the bot will return the first paragraph from the first n dictionary hits")

  def initialize
    super
    @oxurl = "http://www.oxforddictionaries.com/definition/english/%s"
  end

  def help(plugin, topic="")
    'oxford <word>: check for <word> on the oxford english dictionary.'
  end

  def oxford(m, params)
    justcheck = params[:justcheck]

    word = params[:word].join
    [word, word + "_1"].each { |check|
      url = @oxurl % CGI.escape(check)
      if params[:british]
        url << "?view=uk"
      end
      h = @bot.httputil.get(url, :max_redir => 5)
      if h
	defs = h.split("<span class=\"definition\">")
	defs = defs[1..-1].map {|d| d.split("</span>")[0]}
        if defs.size == 0
	  return false if justcheck
	  m.reply "#{word} not found"
	  return false
	end
	m.reply("#{word}: #{url}") unless justcheck
	defn = defs[0]
        m.reply("#{Bold}%s#{Bold}: %s" % [word, defn.ircify_html(:nbsp => :space)], :overlong => :truncate)
        return true
      end
    }
  end

  def is_british?(word)
    return oxford(nil, :word => word, :justcheck => true, :british => true)
  end
end

plugin = OxfordPlugin.new
plugin.map 'oxford *word', :action => 'oxford', :threaded => true

