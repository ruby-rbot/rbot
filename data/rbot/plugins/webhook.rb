# vi:et:sw=2
# webhook plugin -- webservice plugin to support webhooks from common repository services
# (e.g. GitHub, GitLab, Gitea) and announce changes on IRC
# Most of the processing is done through two (sets of) filters:
# * webhook host filters take the JSON sent from the hosting server,
#   and extract pertinent information (repository name, commit author, etc)
# * webhook output filters take the DataStream produced by the webhook host filter,
#   and turn it into an IRC message to be sent by PRIVMSG or NOTICE based on the
#   webhook.announce_method configuration
# The reason for this two-tier filtering is to allow the same output filters
# to be fed data from different (potentially unknown) hosting services.

# TODO for the repo matchers in the built-in filters we might want to support
# both the whole user/repo or just the repo name

# TODO specialized output filter by event/event_key, with some kind of automatic selection
# e.g. if :default_pull_request exists, then it's automatically used if :event => "pull_request"
# and :default is the current output filter.
# The big question is what we should fallback to if the specific filter doesn't exist..
#
# If :custom exists, :default_pull_request exists and :custom_pull_request does not,
# should we fall back to :custom or to :default_pull_request?


require 'json'

class WebHookPlugin < Plugin
  include WebPlugin

  Config.register Config::EnumValue.new('webhook.announce_method',
    :values => ['say', 'notice'],
    :default => 'say',
    :desc => "Whether to send a message or notice when announcing new GitHub actions.")

  # Auxiliary method used to collect two lines for  output filters,
  # running substitutions against DataStream _s_ optionally joined
  # with hash _h_.
  #
  # TODO this was ripped from rss.rb considering moving it to the DataStream
  # interface or something like that
  #
  # For substitutions, *_wrap keys can be used to alter the content of
  # other nonempty keys. If the value of *_wrap is a String, it will be
  # put before and after the corresponding key; if it's an Array, the first
  # and second elements will be used for wrapping; if it's nil, no wrapping
  # will be done (useful to override a default wrapping).
  #
  # For example:
  # :handle_wrap => '::'::
  #   will wrap s[:handle] by prefixing and postfixing it with '::'
  # :date_wrap => [nil, ' :: ']::
  #   will put ' :: ' after s[:date]
  def make_stream(line1, line2, s, h={})
    ss = s.merge(h)
    subs = {}
    wraps = {}
    ss.each do |k, v|
      kk = k.to_s.chomp!('_wrap')
      if kk
        nk = kk.intern
        case v
        when String
          wraps[nk] = ss[nk].wrap_nonempty(v, v)
        when Array
          wraps[nk] = ss[nk].wrap_nonempty(*v)
        when nil
          # do nothing
        else
          warning "ignoring #{v.inspect} wrapping of unknown class"
        end unless ss[nk].nil?
      else
        subs[k] = v
      end
    end
    subs.merge! wraps
    DataStream.new([line1, line2].compact.join("\n") % subs, ss)
  end


  # Auxiliary method used to define rss output filters
  def webhook_host_filter(key, &block)
    @bot.register_filter(key, @hostkey, &block)
  end

  def webhook_out_filter(key, &block)
    @bot.register_filter(key, @outkey, &block)
  end

  # Define the default webhook host and output filters, and load custom ones.
  # Custom filters are looked for in the plugin's default filter locations,
  # and in webhook/filters.rb 
  #
  # Preferably, the webhook_host_filter and webhook_out_filter methods should be used in these files, e.g.:
  #   webhook_filter :my_output do |s|
  #     line1 = "%{repo} and some %{author} info"
  #     make_stream(line1, nil, s)
  #   end
  # to define the new filter 'my_output'.
  #
  # The datastream passed as input to the host filters has two keys:
  # payload::
  #   the hash representing the JSON payload
  # request::
  #   the HTTPRequest that carried the JSON payload
  # repo::
  #   the expected name of the repository.
  #
  # Host filters should check that the request+payload is compatible with the format they expect,
  # and that the detected repo name matches the provided one. If either condition is not satisfied,
  # they should return nil. Otherwise, they should augment the input hash with
  # approrpiate keys extracting the relevant information (as indicated below).
  #
  # The default host and out filters produce and expect the following keys in the DataStream:
  # event::
  #   the event type, as described by e.g. the X-GitHub-Event request header
  # event_key::
  #   the main event-specific object key (e.g. issue in the case of issue_comment)
  # payload::
  #   the hash representing the JSON payload
  # repo::
  #   the full name of the repository (e.g. "ruby-rbot/rbot")
  # author::
  #   the sender login (e.g. "Oblomov")
  # action::
  #   the hook action
  # ref::
  #   the ref referenced by the event
  # number::
  #   the cooked number of the issue or PR modified, or the number of commits; this includes the name of the object or the word 'commits'
  # title::
  #   title of the object
  # link::
  #   the HTML link
  def define_filters
    @hostkey ||= :"webhook.host"
    @outkey ||= :"webhook.out"

    # the default output filter
    webhook_out_filter :default do |s|
      line1 = "%{repo}: %{author} %{action}"
      [:number, :title, :ref, :link].each do |k|
        line1 += "%{#{k}}" if s[k]
      end
      make_stream(line1, nil, s,
                  :repo_wrap => [Irc.color(:yellow), NormalText],
                  :author_wrap => Bold,
                  :number_wrap => [' ', ''],
                  :title_wrap => [" #{Irc.color(:green)}", NormalText],
                  :ref_wrap =>  [" (#{Irc.color(:yellow)}", "#{NormalText})"],
                  :link_wrap => [" <#{Irc.color(:aqualight)}", "#{NormalText}>"])
    end

    # the github host filter is actually implemented below
    webhook_host_filter :github do |s|
      github_host_filter(s)
    end

    # gitea is essentially compatible with github
    webhook_host_filter :gitea do |s|
      github_host_filter(s)
    end

    # gitlab has a different one
    webhook_host_filter :gitlab do |s|
      gitlab_host_filter(s)
    end

    @user_types ||= datafile 'filters.rb'
    load_filters
    load_filters :path => @user_types
  end

  # Map the event name to the payload key storing the essential information
  GITHUB_EVENT_KEY = {
    :issues => :issue,
    :ping => :hook,
  }

  # Host filters should return nil if they cannot process the given payload+request pair
  def github_host_filter(input_stream)
    request = input_stream[:request]
    json = input_stream[:payload]
    req_repo = input_stream[:repo]

    return nil unless request['x-github-event']

    repo = json[:repository]
    return nil unless repo
    repo = repo[:full_name]
    return nil unless repo

    return nil unless repo == req_repo

    event = request.header['x-github-event'].first.to_sym

    obj = nil
    link = nil
    title = nil

    event_key = GITHUB_EVENT_KEY[event] || event

    # :issue_comment needs special handling because it has two primary objects
    # (the issue and the comment), and we take stuff from both
    obj = json[event_key] || json[:issue]
    if obj
      link = json[:comment][:html_url] rescue nil if event == :issue_comment
      link ||= obj[:html_url] || obj[:url]
      title = obj[:title]
    else
      link = json[:html_url] || json[:url] || json[:compare]
    end
    title ||= json[:zen] || json[:commits].last[:message].lines.first.chomp rescue nil

    stream_hash = { :event => event,
                    :event_key => event_key,
                    :ref => json[:ref],
                    :author => (json[:sender][:login] rescue nil),
                    :action => json[:action] || event,
                    :title => title,
                    :link => link
    }

    stream_hash[:ref] ||= json[:base][:ref] if json[:base]

    num = json[:number] || obj[:number] rescue nil
    stream_hash[:number] = '%{object} #%{num}' % { :num => num, :object => event_key.to_s.gsub('_', ' ') } if num
    num = json[:size] || json[:commits].size rescue nil
    stream_hash[:number] = _("%{num} commits") % { :num => num } if num

    case event
    when :watch
      stream_hash[:number] ||= 'watching 👀%{watchers_count}' % json[:repository]
    when :star
      stream_hash[:number] ||= 'star ☆ %{watchers_count}' % json[:repository]
    end

    debug stream_hash

    return input_stream.merge stream_hash
  end

  GITLAB_EVENT_ACTION = {
    'push' => 'pushed',
    'tag_push' => 'pushed tag',
    'note' => 'commented on'
  }

  def gitlab_host_filter(input_stream)
    request = input_stream[:request]
    json = input_stream[:payload]
    req_repo = input_stream[:repo]

    return nil unless request['x-gitlab-event']

    repo = json[:project]
    return nil unless repo
    repo = repo[:path_with_namespace]
    return nil unless repo

    return nil unless repo == req_repo

    event = json[:object_kind]
    if not event
      debug "No object_kind found in JSON"
      return nil
    end

    event_key = :object_attributes
    obj = json[event_key]

    user = json[:user] # may be nil: some events use keys such as user_username
    # TODO we might want to unify this at the rbot level

    # comments have a noteable_type, but this is not the key of the object used
    # so instead we just look for the known keys
    notable = nil
    [:commit, :merge_request, :issue, :snippet].each do |k|
      if json.has_key?(k)
        notable = json[k]
        break
      end
    end

    link = obj ? obj[:url] : nil
    title = notable ? notable[:title] : obj ? obj[:title] : nil
    title ||= json[:commits].last[:title] rescue nil

    # TODO https://docs.gitlab.com/ee/user/project/integrations/webhooks.html

    stream_hash = { :event => event,
                    :event_key => event_key,
                    :ref => json[:ref],
                    :author => user ? user[:username] : json[:user_username],
                    :action => GITLAB_EVENT_ACTION[event] || (obj ? (obj[:action] || 'created') :  event),
                    :title => title,
                    :link => link,
                    :text => obj ? (obj[:note] || obj[:description]) : nil
    }

    stream_hash[:ref] ||= obj[:target_branch] if obj

    num = notable ? (notable[:iid] || notable[:id]) : obj ? obj[:iid] || obj[:id] : nil
    stream_hash[:number] = '%{object} #%{num}' % { :num => num, :object => (obj[:noteable_type] || event).to_s.gsub('_', ' ') } if num
    num = json[:total_commits_count]
    stream_hash[:number] = _("%{num} commits") % { :num => num } if num

    debug stream_hash
    return input_stream.merge stream_hash
  end

  def initialize
    super
    define_filters

    # @repos is hash the maps each reapo to a hash of watchers
    # channel => filter
    @repos = {}
    if @registry.has_key?(:repos)
      @repos = @registry[:repos]
    end
  end

  def name
    "webhook"
  end

  def save
    @registry[:repos] = Hash.new.merge @repos
  end

  def help(plugin, topic = '')
    case topic
    when "watch"
      ["webhook watch #{Bold}repository#{Bold} #{Bold}filter#{Bold} [in #{Bold}\#channel#{Bold}]: announce webhook triggers matching the given repository, using the given output filter.",
       "the repository should be defined as service:name where service is known service, and name the actual repository name.",
       "example: webhook watch github:ruby-rbot/rbot github"].join("\n")
    when "unwatch"
      " unwatch #{Bold}repository#{Bold} [in #{Bold}\#channel#{Bold}]: stop announcing webhhoks from the given repository"
    else
      " [un]watch <repository> [in #channel]: manage webhhok announcements for the given repository in the given channel"
    end
  end

  def watch_repo(m, params)
    repo = params[:repo]
    chan = (params[:chan] || m.replyto).downcase
    filter = params[:filter] || :default

    @repos[repo] ||= {}
    @repos[repo][chan] = filter
    m.okay
  end

  def unwatch_repo(m, params)
    repo = params[:repo]
    chan = (params[:chan] || m.replyto).downcase

    if @repos.has_key?(repo)
      @repos[repo].delete(chan)
      m.okay
      if @repos[repo].empty?
        @repos.delete(repo)
        m.reply _("No more watchers, I'll forget about %{repo} altogether") % params
      end
    else
      m.reply _("repo %{repo} not found") % params
    end
  end

  # Display the host filters
  def list_host_filters(m, params)
    ar = @bot.filter_names(@hostkey)
    if ar.empty?
      m.reply _("No custom service filters registered")
    else
      m.reply ar.map { |k| k.to_s }.sort!.join(", ")
    end
  end

  # Display the known output filters
  def list_output_filters(m, params)
    ar = @bot.filter_names(@outkey)
    ar.delete(:default)
    if ar.empty?
      m.reply _("No custom output filters registered")
    else
      m.reply ar.map { |k| k.to_s }.sort!.join(", ")
    end
  end

  # Display the known repos and watchers
  def list_repos(m, params)
    if @repos.empty?
      m.reply "No repos defined"
      return
    end
    msg = @repos.map do |repo, watchers|
      [Bold + repo + Bold, watchers.map do |channel, filter|
        "#{channel} (#{filter})"
      end.join(", ")].join(": ")
    end.join(", ")
    m.reply msg
  end

  def filter_hook(json, request)
    announce_method = @bot.config['webhook.announce_method']

    debug request
    debug json

    @repos.each do |s_repo, watchers|
      host, repo = s_repo.split(':', 2)
      key = @bot.global_filter_name(host, @hostkey)
      error "No host filter for #{host} (from #{s_repo})" unless @bot.has_filter?(key)

      debug key
      processed = @bot.filter(key, { :payload => json, :request => request, :repo => repo })
      debug processed
      next unless processed

      # TODO if we see that the same output filter is applied to multiple channels,
      # we should group the channels by filters and only do the output processing once
      watchers.each do |channel, filter|
        begin
          key = @bot.global_filter_name(filter, @outkey)
          key = @bot.global_filter_name(:default, @outkey) unless @bot.has_filter?(key)

          debug key
          output = @bot.filter(key, processed)
          debug output

          @bot.__send__(announce_method, channel, output)
        rescue => e
          error "Failed to announce #{json} for #{repo} in #{channel} with filter #{filter}"
          debug e.inspect
          debug e.backtrace.join("\n") if e.respond_to?(:backtrace)
        end
      end
      # match found, stop checking
      break
    end
  end

  def process_hook(m, params)
    json = nil
    begin
      json = JSON.parse(m.req.body, :symbolize_names => true)
    rescue => e
      error "Failed to parse request #{m.req}"
      debug m.req
      debug e.inspect
      debug e.backtrace.join("\n") if e.respond_to?(:backtrace)
    end

    # Send the response early
    if not json
      m.send_plaintext("Failed\n", 400)
      return
    end

    m.send_plaintext("OK\n", 200)

    begin
      filter_hook(json, m.req)
    rescue => e
      error e
      debug e.inspect
      debug e.backtrace.join("\n") if e.respond_to?(:backtrace)
    end
  end

end

plugin = WebHookPlugin.new
plugin.web_map "/webhook", :action => :process_hook

plugin.map 'webhook watch :repo :filter [in :chan]',
  :action => :watch_repo,
  :defaults => { :filter => nil }

plugin.map 'webhook unwatch :repo [in :chan]',
  :action => :unwatch_repo

plugin.map 'webhook list [repos]',
  :action => 'list_repos'

plugin.map 'webhook [list] filters',
  :action => 'list_output_filters'

plugin.map 'webhook [list] hosts',
  :action => 'list_host_filters'

plugin.map 'webhook [list] services',
  :action => 'list_host_filters'
