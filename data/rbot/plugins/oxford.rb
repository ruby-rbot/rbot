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
require 'uri'

class OxfordPlugin < Plugin
  Config.register Config::IntegerValue.new(
    'oxford.max_lines',
    :default => 1,
    :desc => 'The number of lines to respond with.')

  def initialize
    super
    @base_url = "https://www.lexico.com"
  end

  def help(plugin, topic = '')
    'oxford <word>: check for <word> on the lexico english dictionary (powered by oxford english dictionary).'
  end

  def oxford(m, params)
    word = params[:word].join(' ')

    url = "#{@base_url}/definition/#{URI::encode word}"

    begin
      debug "searching definition for #{word.inspect}"

      response = @bot.httputil.get(url, resp: true)
      definition = parse_definition(response)

      # try to find alternative word (different spelling, typos, etc.)
      if definition.empty?
        debug "search for alternative spelling result"
        url = title = nil
        exact_matches = response.xpath('//div[@class="no-exact-matches"]//ul/li/a')
        if not exact_matches.empty? and not exact_matches.first['href'].empty?
          url = @base_url + exact_matches.first['href']
          title = exact_matches.first.content
        else
          debug 'use web-service to find alternative result'
          # alternatively attempt to use their webservice (json-p) instead
          url = "#{@base_url}/search/dataset.js?dataset=noad&dictionary=en&query=#{CGI.escape word}"
          response = @bot.httputil.get(url, headers: {'X-Requested-With': 'XMLHttpRequest'})
          alternative = response.gsub(/\\/, '').scan(/href="([^"]+)">([^<]+)</)
          unless alternative.empty?
            url = @base_url + alternative.first[0]
            title = alternative.first[1]
          end
        end

        debug "search for alternative spelling result, returned title=#{title.inspect} url=#{url.inspect}"

        if url and title
          unless title.downcase == word.downcase
            m.reply "did you mean: #{Bold}#{title.ircify_html}#{NormalText}?"
          end
          response = @bot.httputil.get(url, resp: true)
          definition = parse_definition(response)
        end
      end
    rescue => e
      m.reply "error accessing lexico url -> #{url}"
      error e
      return
    end

    unless definition.empty?
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

