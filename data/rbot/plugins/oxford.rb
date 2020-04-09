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
require 'cgi'

class OxfordPlugin < Plugin
  Config.register Config::IntegerValue.new(
    'oxford.max_lines',
    :default => 1,
    :desc => 'The number of lines to respond with.')

  def initialize
    super
    @base_url = "https://www.lexico.com"
  end

  def help(plugin, topic="")
    'oxford <word>: check for <word> on the lexico english dictionary (powered by oxford english dictionary).'
  end

  def oxford(m, params)
    word = params[:word].join

    url = "#{@base_url}/definition/#{CGI.escape word}"

    begin
      response = @bot.httputil.get(url, resp: true)
      definition = parse_definition(response)

      if definition.empty?
        closest = response.xpath('//div[@class="no-exact-matches"]//ul/li/a').first

        url = @base_url + closest['href']

        m.reply "did you mean: #{Bold}#{closest.content.ircify_html}#{NormalText}"

        response = @bot.httputil.get(url, resp: true)
        definition = parse_definition(response)
      end
    rescue => e
      m.reply "error accessing lexico url -> #{url}"
      error e
      return
    end

    if definition
      m.reply definition.ircify_html, max_lines: @bot.config['oxford.max_lines']
    else
      m.reply "couldn't find a definition for #{word} on oxford dictionary"
    end
  end

  private

  def parse_definition(r)
    r.xpath('//section[@class="gramb"]//text()').map(&:content).join(' ')
  end
end

plugin = OxfordPlugin.new
plugin.map 'oxford *word', :action => 'oxford', :threaded => true

