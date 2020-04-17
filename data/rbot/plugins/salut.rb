#-- vim:sw=2:et
#++
#
# :title: Salutations plugin for rbot
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2006-2007 Giuseppe Bilotta
# License:: GPL v2
#
# Salutations plugin: respond to salutations
#
# TODO:: allow online editing of salutations

class SalutPlugin < Plugin
  Config.register Config::BooleanValue.new('salut.all_languages',
    :default => true,
    :desc => "Check for a salutation in all languages and not just in the one defined by core.language",
    :on_change => Proc.new {|bot, v| bot.plugins['salut'].reload})

  Config.register Config::BooleanValue.new('salut.address_only',
    :default => true,
    :desc => "When set to true, the bot will only reply to salutations directed at him",
    :on_change => Proc.new {|bot, v| bot.plugins['salut'].reload})

  def initialize
    super

    @match = Hash.new
    @match_langs = Array.new

    reload
  end

  def set_language(language)
    @language = language
  end

  def load_static_files(path)
    debug "loading salutation rules from #{path}"
    Dir.glob("#{path}/*").map { |filename|
      language = filename[filename.rindex('-')+1..-1]
      begin
        salutations = {}
        content = YAML::load_file(filename)
        content.each { |key, val|
          salutations[key.to_sym] = val
        }
      rescue
        error "failed to read salutations in #{filename}: #{$!}"
      end
      [language, salutations]
    }.to_h
  end

  def reload
    @salutations = @registry[:salutations]

    # migrate existing data files
    if not @salutations and Dir.exists? datafile
      log "migrate existing salutations from #{datafile}"

      @salutations = load_static_files(datafile)
    end

    # load initial salutations from plugin directory
    unless @salutations
      log "load initial salutations from #{plugin_path}"

      initial_path = File.join(plugin_path, 'salut')
      @salutations = load_static_files(initial_path)
    end

    debug @salutations.inspect

    create_match
  end

  def save
    return unless @salutations

    @registry[:salutations] = @salutations

    @registry.flush
  end

  def create_match
    use_all_languages = @bot.config['salut.all_languages']

    @match.clear
    ar_dest = Array.new
    ar_in = Array.new
    ar_out = Array.new
    ar_both = Array.new
    @salutations.each { |lang, hash|
      next if lang != @language and not use_all_languages
      ar_dest.clear
      ar_in.clear
      ar_out.clear
      ar_both.clear
      hash.each { |situation, array|
        case situation.to_s
        when /^generic-dest$/
          ar_dest += array
        when /in$/
          ar_in += array
        when /out$/
          ar_out += array
        else
          ar_both += array
        end
      }
      @match[lang] = Hash.new
      @match[lang][:in] = Regexp.new("\\b(?:" + ar_in.uniq.map { |txt|
        Regexp.escape(txt)
      }.join('|') + ")\\b", Regexp::IGNORECASE) unless ar_in.empty?
      @match[lang][:out] = Regexp.new("\\b(?:" + ar_out.uniq.map { |txt|
        Regexp.escape(txt)
      }.join('|') + ")\\b", Regexp::IGNORECASE) unless ar_out.empty?
      @match[lang][:both] = Regexp.new("\\b(?:" + ar_both.uniq.map { |txt|
        Regexp.escape(txt)
      }.join('|') + ")\\b", Regexp::IGNORECASE) unless ar_both.empty?
      @match[lang][:dest] = Regexp.new("\\b(?:" + ar_dest.uniq.map { |txt|
        Regexp.escape(txt)
      }.join('|') + ")\\b", Regexp::IGNORECASE) unless ar_dest.empty?
    }
    @punct = /\s*[.,:!;?]?\s*/ # Punctuation

    # Languages to match for, in order
    @match_langs.clear
    @match_langs << @language if @match.key?(@language)
    @match_langs << 'english' if @match.key?('english')
    @match.each_key { |key|
      @match_langs << key
    }
    @match_langs.uniq!
  end

  def unreplied(m)
    return if @match.empty?
    return unless m.kind_of?(PrivMessage)
    return if m.address? and m.plugin == 'config'
    to_me = m.address? || m.message =~ /#{Regexp.escape(@bot.nick)}/i
    if @bot.config['salut.address_only']
      return unless to_me
    end
    salut = nil
    @match_langs.each { |lang|
      [:both, :in, :out].each { |k|
        next unless @match[lang][k]
        if m.message =~ @match[lang][k]
          salut = [@match[lang][k], lang, k]
          break
        end
      }
      break if salut
    }
    return unless salut
    # If the bot wasn't addressed, we continue only if the match was exact
    # (apart from space and punctuation) or if @match[:dest] matches too
    return unless to_me or m.message =~ /^#{@punct}#{salut.first}#{@punct}$/ or m.message =~ @match[salut[1]][:dest]
    h = Time.new.hour
    case h
    when 4...12
      salut_reply(m, salut, :morning)
    when 12...18
      salut_reply(m, salut, :afternoon)
    else
      salut_reply(m, salut, :evening)
    end
  end

  def salut_reply(m, salut, time)
    lang = salut[1]
    k = salut[2]
    debug "Replying to #{salut.first} (#{lang} #{k}) in the #{time}"
    salut_ar = @salutations[lang]
    case k
    when :both
      sfx = ""
    else
      sfx = "-#{k}"
    end
    debug "Building array ..."
    rep_ar = Array.new
    rep_ar += salut_ar.fetch("#{time}#{sfx}".to_sym, [])
    rep_ar += salut_ar.fetch("#{time}".to_sym, []) unless sfx.empty?
    rep_ar += salut_ar.fetch("generic#{sfx}".to_sym, [])
    rep_ar += salut_ar.fetch("generic".to_sym, []) unless sfx.empty?
    debug "Choosing reply in #{rep_ar.inspect} ..."
    if rep_ar.empty?
      if m.public? # and (m.address? or m =~ /#{Regexp.escape(@bot.nick)}/)
        choice = @bot.lang.get("hello_X") % m.sourcenick
      else
        choice = @bot.lang.get("hello") % m.sourcenick
      end
    else
      choice = rep_ar.pick_one
      if m.public? and (m.address? or m.message =~ /#{Regexp.escape(@bot.nick)}/)
        choice += "#{[',',''].pick_one} #{m.sourcenick}"
        choice += [" :)", " :D", "!", "", "", ""].pick_one
      end
    end
    debug "Replying #{choice}"
    m.reply choice, :nick => false, :to => :public
  end
end

SalutPlugin.new
