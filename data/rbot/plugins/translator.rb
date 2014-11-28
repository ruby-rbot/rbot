#-- vim:sw=2:et
#++
#
# :title: Translator plugin for rbot
#
# Author:: Yaohan Chen <yaohan.chen@gmail.com>
# Copyright:: (C) 2007 Yaohan Chen
# License:: GPLv2
#
# This plugin allows using rbot to translate text on a few translation services
#
# TODO
#
# * Configuration for whether to show translation engine
# * Optionally sync default translators with karma.rb ranking

require 'set'
require 'timeout'

# base class for implementing a translation service
# = Attributes
# direction:: supported translation directions, a hash where each key is a source
#             language name, and each value is Set of target language names. The
#             methods in the Direction module are convenient for initializing this
#             attribute
class Translator
  INFO = 'Some translation service'

  class UnsupportedDirectionError < ArgumentError
  end

  class NoTranslationError < RuntimeError
  end

  attr_reader :directions, :cache

  def initialize(directions, cache={})
    @directions = directions
    @cache = cache
  end

  # Many translators use Mechanize, which changed namespace around version 1.0
  # To support both pre-1.0 and post-1.0 namespaces, we use these auxiliary
  # method. The translator still needs to require 'mechanize' on initialization
  # if it needs it.
  def mechanize
    return Mechanize if defined? Mechanize
    return WWW::Mechanize
  end

  # whether the translator supports this direction
  def support?(from, to)
    from != to && @directions[from].include?(to)
  end

  # this implements argument checking and caching. subclasses should define the
  # do_translate method to implement actual translation
  def translate(text, from, to)
    raise UnsupportedDirectionError unless support?(from, to)
    raise ArgumentError, _("Cannot translate empty string") if text.empty?
    request = [text, from, to]
    unless @cache.has_key? request
      translation = do_translate(text, from, to)
      raise NoTranslationError if translation.empty?
      @cache[request] = translation
    else
      @cache[request]
    end
  end

  module Direction
    # given the set of supported languages, return a hash suitable for the directions
    # attribute which includes any language to any other language
    def self.all_to_all(languages)
      directions = all_to_none(languages)
      languages.each {|l| directions[l] = languages.to_set}
      directions
    end

    # a hash suitable for the directions attribute which includes any language from/to
    # the given set of languages (center_languages)
    def self.all_from_to(languages, center_languages)
      directions = all_to_none(languages)
      center_languages.each {|l| directions[l] = languages - [l]}
      (languages - center_languages).each {|l| directions[l] = center_languages.to_set}
      directions
    end

    # get a hash from a list of pairs
    def self.pairs(list_of_pairs)
      languages = list_of_pairs.flatten.to_set
      directions = all_to_none(languages)
      list_of_pairs.each do |(from, to)|
        directions[from] << to
      end
      directions
    end

    # an empty hash with empty sets as default values
    def self.all_to_none(languages)
      Hash.new do |h, k|
        # always return empty set when the key is non-existent, but put empty set in the
        # hash only if the key is one of the languages
        if languages.include? k
          h[k] = Set.new
        else
          Set.new
        end
      end
    end
  end
end

class GoogleTranslator < Translator
  INFO = 'Google Translate <http://www.google.com/translate_t>'
  URL = 'https://translate.google.com/'

  LANGUAGES =
    %w[af sq am ar hy az eu be bn bh bg my ca chr zh zh_CN zh_TW hr
    cs da dv en eo et tl fi fr gl ka de el gn gu iw hi hu is id iu
    ga it ja kn kk km ko lv lt mk ms ml mt mr mn ne no or ps fa pl
    pt_PT pa ro ru sa sr sd si sk sl es sw sv tg ta tl te th bo tr
    uk ur uz ug vi cy yi auto]
  def initialize(cache={})
    require 'mechanize'
    super(Translator::Direction.all_to_all(LANGUAGES), cache)
  end

  def do_translate(text, from, to)
    agent = Mechanize.new
    agent.user_agent_alias = 'Linux Mozilla'
    page = agent.get URL
    form = page.form_with(:id => 'gt-form')
    form.sl = from
    form.tl = to
    form.text = text
    page = form.submit
    return page.search('#result_box span').first.content
  end
end

class YandexTranslator < Translator
  INFO = 'Yandex Translator <http://translate.yandex.com/>'
  LANGUAGES = %w{ar az be bg ca cs da de el en es et fi fr he hr hu hy it ka lt lv mk nl no pl pt ro ru sk sl sq sr sv tr uk}

  URL = 'https://translate.yandex.net/api/v1.5/tr.json/translate?key=%s&lang=%s-%s&text=%s'
  KEY = 'trnsl.1.1.20140326T031210Z.1e298c8adb4058ed.d93278fea8d79e0a0ba76b6ab4bfbf6ac43ada72'
  def initialize(cache)
    require 'uri'
    require 'json'
    super(Translator::Direction.all_to_all(LANGUAGES), cache)
  end

  def translate(text, from, to)
    res = Irc::Utils.bot.httputil.get_response(URL % [KEY, from, to, URI.escape(text)])
    res = JSON.parse(res.body)

    if res['code'] != 200
      raise Translator::NoTranslationError
    else
      res['text'].join(' ')
    end
  end

end

class TranslatorPlugin < Plugin
  Config.register Config::IntegerValue.new('translator.timeout',
    :default => 30, :validate => Proc.new{|v| v > 0},
    :desc => _("Number of seconds to wait for the translation service before timeout"))
  Config.register Config::StringValue.new('translator.destination',
    :default => "en",
    :desc => _("Default destination language to be used with translate command"))

  TRANSLATORS = {
    'google_translate' => GoogleTranslator,
    'yandex' => YandexTranslator,
  }

  def initialize
    super
    @failed_translators = []
    @translators = {}
    TRANSLATORS.each_pair do |name, c|
      watch_for_fail(name) do
        @translators[name] = c.new(@registry.sub_registry(name))
        map "#{name} :from :to *phrase",
          :action => :cmd_translate, :thread => true
      end
    end

    Config.register Config::ArrayValue.new('translator.default_list',
      :default => TRANSLATORS.keys,
      :validate => Proc.new {|l| l.all? {|t| TRANSLATORS.has_key?(t)}},
      :desc => _("List of translators to try in order when translator name not specified"),
      :on_change => Proc.new {|bot, v| update_default})
    update_default
  end

  def watch_for_fail(name, &block)
    begin
      yield
    rescue Exception
      debug 'Translator error: '+$!.to_s
      debug $@.join("\n")
      @failed_translators << { :name => name, :reason => $!.to_s }

      warning _("Translator %{name} cannot be used: %{reason}") %
             {:name => name, :reason => $!}
      map "#{name} [*args]", :action => :failed_translator,
                             :defaults => {:name => name, :reason => $!}
    end
  end

  def failed_translator(m, params)
    m.reply _("Translator %{name} cannot be used: %{reason}") %
            {:name => params[:name], :reason => params[:reason]}
  end

  def help(plugin, topic=nil)
    case (topic.intern rescue nil)
    when :failed
      unless @failed_translators.empty?
        failed_list = @failed_translators.map { |t| _("%{bold}%{translator}%{bold}: %{reason}") % {
          :translator => t[:name],
          :reason => t[:reason],
          :bold => Bold
        }}

        _("Failed translators: %{list}") % { :list => failed_list.join(", ") }
      else
        _("None of the translators failed")
      end
    else
      if @translators.has_key?(plugin)
        translator = @translators[plugin]
        _('%{translator} <from> <to> <phrase> => Look up phrase using %{info}, supported from -> to languages: %{directions}') % {
          :translator => plugin,
          :info => translator.class::INFO,
          :directions => translator.directions.map do |source, targets|
                           _('%{source} -> %{targets}') %
                           {:source => source, :targets => targets.to_a.join(', ')}
                         end.join(' | ')
        }
      else
        help_str = _('Command: <translator> <from> <to> <phrase>, where <translator> is one of: %{translators}. If "translator" is used in place of the translator name, the first translator in translator.default_list which supports the specified direction will be picked automatically. Use "help <translator>" to look up supported from and to languages') %
                     {:translators => @translators.keys.join(', ')}

        help_str << "\n" + _("%{bold}Note%{bold}: %{failed_amt} translators failed, see %{reverse}%{prefix}help translate failed%{reverse} for details") % {
          :failed_amt => @failed_translators.size,
          :bold => Bold,
          :reverse => Reverse,
          :prefix => @bot.config['core.address_prefix'].first
        }

        help_str
      end
    end
  end

  def languages
    @languages ||= @translators.map { |t| t.last.directions.keys }.flatten.uniq
  end

  def update_default
    @default_translators = bot.config['translator.default_list'] & @translators.keys
  end

  def cmd_translator(m, params)
    params[:to] = @bot.config['translator.destination'] if params[:to].nil?
    params[:from] ||= 'auto'
    translator = @default_translators.find {|t| @translators[t].support?(params[:from], params[:to])}

    if translator
      cmd_translate m, params.merge({:translator => translator, :show_provider => false})
    else
      # When translate command is used without source language, "auto" as source
      # language is assumed. It means that google translator is used and we let google
      # figure out what the source language is.
      #
      # Problem is that the google translator will fail if the system that the bot is
      # running on does not have the json gem installed.
      if params[:from] == 'auto'
        m.reply _("Unable to auto-detect source language due to broken google translator, see %{reverse}%{prefix}help translate failed%{reverse} for details") % {
          :reverse => Reverse,
          :prefix => @bot.config['core.address_prefix'].first
        }
      else
        m.reply _('None of the default translators (translator.default_list) supports translating from %{source} to %{target}') % {:source => params[:from], :target => params[:to]}
      end
    end
  end

  def cmd_translate(m, params)
    # get the first word of the command
    tname = params[:translator] || m.message[/\A(\w+)\s/, 1]
    translator = @translators[tname]
    from, to, phrase = params[:from], params[:to], params[:phrase].to_s
    if translator
      watch_for_fail(tname) do
        begin
          translation = Timeout.timeout(@bot.config['translator.timeout']) do
            translator.translate(phrase, from, to)
          end
          m.reply(if params[:show_provider]
                    _('%{translation} (provided by %{translator})') %
                      {:translation => translation, :translator => tname.gsub("_", " ")}
                  else
                    translation
                  end)

        rescue Translator::UnsupportedDirectionError
          m.reply _("%{translator} doesn't support translating from %{source} to %{target}") %
                  {:translator => tname, :source => from, :target => to}
        rescue Translator::NoTranslationError
          m.reply _('%{translator} failed to provide a translation') %
                  {:translator => tname}
        rescue Timeout::Error
          m.reply _('The translator timed out')
        end
      end
    else
      m.reply _('No translator called %{name}') % {:name => tname}
    end
  end

  # URL translation has nothing to do with Translators so let's make it
  # separate, and Google exclusive for now
  def cmd_translate_url(m, params)
    params[:to] = @bot.config['translator.destination'] if params[:to].nil?
    params[:from] ||= 'auto'

    translate_url = "http://translate.google.com/translate?sl=%{from}&tl=%{to}&u=%{url}" % {
      :from => params[:from],
      :to   => params[:to],
      :url  => CGI.escape(params[:url].to_s)
    }

    m.reply(translate_url)
  end
end

plugin = TranslatorPlugin.new
req = Hash[*%w(from to).map { |e| [e.to_sym, /#{plugin.languages.join("|")}/] }.flatten]

plugin.map 'translate [:from] [:to] :url',
           :action => :cmd_translate_url, :requirements => req.merge(:url => %r{^https?://[^\s]*})
plugin.map 'translator [:from] [:to] :url',
           :action => :cmd_translate_url, :requirements => req.merge(:url => %r{^https?://[^\s]*})
plugin.map 'translate [:from] [:to] *phrase',
           :action => :cmd_translator, :thread => true, :requirements => req
plugin.map 'translator [:from] [:to] *phrase',
           :action => :cmd_translator, :thread => true, :requirements => req
