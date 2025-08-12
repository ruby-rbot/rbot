#-- vim:sw=2:et
#++
#
# :title: lart/praise plugin for rbot
#
# Author::    Michael Brailsford  <brailsmt@yahoo.com> aka brailsmt
# Author::    Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# Copyright:: (C) 2002 Michael Brailsford.  All rights reserved.
# Copyright:: (C) 2006 Giuseppe Bilotta.  All rights reserved.
#
# License::  This plugin is licensed under the BSD license.  The terms of
#            which follow.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# Purpose::   Provide for humorous larts and praises

class LartPlugin < Plugin

  def initialize
    @larts = nil
    @praises = nil

    super
    # after initialization #set_language is called with the language set in the bot configuration
    # this loads the larts/praises from the registry
  end

  def load_static_files(path, suffix)
    entries = {}
    Dir.glob("#{path}/#{suffix}-*").each { |filename|
      language = filename[filename.rindex('-')+1..-1]
      entries[language] = File.readlines(filename).map(&:chomp)
    }
    entries
  end

  def set_language(lang)
    save

    @lang = lang
    @larts = @registry[:larts]
    @praises = @registry[:praises]

    # for migrations try to read lart from bot data first (this is usually in ~/.rbot/lart:
    if (not @larts or not @praises) and Dir.exist? datafile
      log "migrate existing larts or praises from #{datafile}"

      @larts = load_static_files(datafile, 'larts')
      @praises = load_static_files(datafile, 'praises')
    end

    # without migrations, the initial data files we load from is located in the plugin directory
    # that is the directory in which the plugin file itself is located (.../data/rbot/plugins/ usually)
    if not @larts or not @praises
      log "load initial larts and praises from #{plugin_path}"

      initial_path = File.join(plugin_path, 'lart')
      @larts = load_static_files(initial_path, 'larts')
      @praises = load_static_files(initial_path, 'praises')
    end
  end

  def larts
    @larts[@lang]
  end

  def praises
    @praises[@lang]
  end

  def save
    return unless @larts

    @registry[:larts] = @larts
    @registry[:praises] = @praises

    @registry.flush
  end

  def help(plugin, topic = '')
    "Lart: The lart plugin allows you to lart/praise someone in the channel. You can also add new larts and new praises as well as delete them. For the curious, LART is an acronym for Luser Attitude Readjustment Tool. Usage: lart <who> [<reason>] -- larts <who> for <reason>. praise <who> [<reason>] -- praises <who> for <reason>. [add|rm][lart|praise] -- Add or remove a lart or praise."
  end

  def handle_lart(m, params)
    lart = larts[get_msg_idx(larts.length)]
    if not lart
      m.reply "I dunno any larts"
      return
    end
    who = params[:who].to_s
    reason = params[:why]
    if who == "me"
      who = m.sourcenick
    end
    if who == @bot.nick
      who = m.sourcenick
      reason = "for trying to make me lart myself"
    end
    lart = replace_who lart, who
    lart << " #{reason}" unless reason.empty?

    m.act lart
  end

  def handle_praise(m, params)
    praise = praises[get_msg_idx(praises.length)]
    if not praise
      m.reply "I dunno any praises"
      return
    end
    who = params[:who].to_s
    reason = params[:why]
    if who == m.sourcenick || who == "me"
      params[:who] = m.sourcenick
      params[:why] = "for praising himself"
      handle_lart(m, params)
      return
    end
    praise = replace_who praise, who
    praise << " #{reason}" unless reason.empty?

    m.act praise
  end

  def handle_addlart(m, params)
    @larts[@lang] << params[:lart].to_s
    @changed = true
    m.okay
  end

  def handle_rmlart(m, params)
    @larts[@lang].delete params[:lart].to_s
    @changed = true
    m.okay
  end

  def handle_listlart(m, params)
    rx = Regexp.new(params[:lart].to_s, true)
    list = larts.grep(rx)
    unless list.empty?
      m.reply list.join(" | "), :split_at => /\s+\|\s+/
    else
      m.reply "no lart found matching #{params[:lart]}"
    end
  end

  def handle_addpraise(m, params)
    @praises[@lang] << params[:praise].to_s
    @changed = true
    m.okay
  end

  def handle_rmpraise(m, params)
    @praises[@lang].delete params[:praise].to_s
    @changed = true
    m.okay
  end

  def handle_listpraise(m, params)
    rx = Regexp.new(params[:praise].to_s, true)
    list = praises.grep(rx)
    unless list.empty?
      m.reply list.join(" | "), :split_at => /\s+\|\s+/
    else
      m.reply "no praise found matching #{params[:praise]}"
    end
  end

  #  The following are utils for larts/praises
  def replace_who(msg, nick)
    msg.gsub(/<who>/i, "#{nick}")
  end

  def get_msg_idx(max)
    rand(max)
  end

end

plugin = LartPlugin.new

plugin.map "lart *who [*why]", :requirements => { :why => /(?:for|because)\s+.*/ }, :action => :handle_lart
plugin.map "praise *who [*why]", :requirements => { :why => /(?:for|because)\s+.*/ }, :action => :handle_praise

plugin.map "addlart *lart", :action => :handle_addlart
plugin.map "addpraise *praise", :action => :handle_addpraise

plugin.map "rmlart *lart", :action => :handle_rmlart
plugin.map "rmpraise *praise", :action => :handle_rmpraise

plugin.map "listlart *lart", :action => :handle_listlart
plugin.map "listpraise *praise", :action => :handle_listpraise
