#-- vim:sw=2:et
#++
#
# :title: rbot plugin management

require 'singleton'
require_relative './core/utils/where_is.rb'

module Irc
class Bot
    Config.register Config::ArrayValue.new('plugins.blacklist',
      :default => [], :wizard => false, :requires_rescan => true,
      :desc => "Plugins that should not be loaded")
    Config.register Config::ArrayValue.new('plugins.whitelist',
      :default => [], :wizard => false, :requires_rescan => true,
      :desc => "Only whitelisted plugins will be loaded unless the list is empty")
module Plugins
  require 'rbot/messagemapper'

=begin rdoc
  BotModule is the base class for the modules that enhance the rbot
  functionality. Rather than subclassing BotModule, however, one should
  subclass either CoreBotModule (reserved for system modules) or Plugin
  (for user plugins).

  A BotModule interacts with Irc events by defining one or more of the following
  methods, which get called as appropriate when the corresponding Irc event
  happens.

  map(template, options)::
  map!(template, options)::
     map is the new, cleaner way to respond to specific message formats without
     littering your plugin code with regexps, and should be used instead of
     #register() and #privmsg() (see below) when possible.

     The difference between map and map! is that map! will not register the new
     command as an alternative name for the plugin.

     Examples:

       plugin.map 'pointstats', :action => 'point_stats'

       # while in the plugin...
       def point_stats(m, params)
         m.reply "..."
       end

       # the default action is the first component
       plugin.map 'points'

       # attributes can be pulled out of the match string
       plugin.map 'points for :key'
       plugin.map 'points :key'

       # while in the plugin...
       def points(m, params)
         item = params[:key]
         m.reply 'points for #{item}'
       end

       # you can setup defaults, to make parameters optional
       plugin.map 'points :key', :defaults => {:key => 'defaultvalue'}

       # the default auth check is also against the first component
       # but that can be changed
       plugin.map 'pointstats', :auth => 'points'

       # maps can be restricted to public or private message:
       plugin.map 'pointstats', :private => false
       plugin.map 'pointstats', :public => false

     See MessageMapper#map for more information on the template format and the
     allowed options.

  listen(UserMessage)::
                         Called for all messages of any type. To
                         differentiate them, use message.kind_of? It'll be
                         either a PrivMessage, NoticeMessage, KickMessage,
                         QuitMessage, PartMessage, JoinMessage, NickMessage,
                         etc.

  ctcp_listen(UserMessage)::
                         Called for all messages that contain a CTCP command.
                         Use message.ctcp to get the CTCP command, and
                         message.message to get the parameter string. To reply,
                         use message.ctcp_reply, which sends a private NOTICE
                         to the sender.

  message(PrivMessage)::
                         Called for all PRIVMSG. Hook on this method if you
                         need to handle PRIVMSGs regardless of whether they are
                         addressed to the bot or not, and regardless of

  privmsg(PrivMessage)::
                         Called for a PRIVMSG if the first word matches one
                         the plugin #register()ed for. Use m.plugin to get
                         that word and m.params for the rest of the message,
                         if applicable.

  unreplied(PrivMessage)::
                         Called for a PRIVMSG which has not been replied to.

  notice(NoticeMessage)::
                         Called for all Notices. Please notice that in general
                         should not be replied to.

  kick(KickMessage)::
                         Called when a user (or the bot) is kicked from a
                         channel the bot is in.

  invite(InviteMessage)::
                         Called when the bot is invited to a channel.

  join(JoinMessage)::
                         Called when a user (or the bot) joins a channel

  part(PartMessage)::
                         Called when a user (or the bot) parts a channel

  quit(QuitMessage)::
                         Called when a user (or the bot) quits IRC

  nick(NickMessage)::
                         Called when a user (or the bot) changes Nick
  modechange(ModeChangeMessage)::
                         Called when a User or Channel mode is changed
  topic(TopicMessage)::
                         Called when a user (or the bot) changes a channel
                         topic

  welcome(WelcomeMessage)::
                         Called when the welcome message is received on
                         joining a server successfully.

  motd(MotdMessage)::
                         Called when the Message Of The Day is fully
                         received from the server.

  connect::              Called when a server is joined successfully, but
                         before autojoin channels are joined (no params)

  set_language(String)::
                         Called when the user sets a new language
                         whose name is the given String

  save::                 Called when you are required to save your plugin's
                         state, if you maintain data between sessions

  cleanup::              called before your plugin is "unloaded", prior to a
                         plugin reload or bot quit - close any open
                         files/connections or flush caches here
=end

  class BotModule
    # the associated bot
    attr_reader :bot

    # the plugin registry
    attr_reader :registry

    # the message map handler
    attr_reader :handler

    # the directory in which the plugin is located
    attr_reader :plugin_path

    # Initialise your bot module. Always call super if you override this method,
    # as important variables are set up for you:
    #
    # @bot::
    #   the rbot instance
    # @registry::
    #   the botmodule's registry, which can be used to store permanent data
    #   (see Registry::Accessor for additional documentation)
    #
    # Other instance variables which are defined and should not be overwritten
    # byt the user, but aren't usually accessed directly, are:
    #
    # @manager::
    #   the plugins manager instance
    # @botmodule_triggers::
    #   an Array of words this plugin #register()ed itself for
    # @handler::
    #   the MessageMapper that handles this plugin's maps
    #
    def initialize
      @manager = Plugins::manager
      @bot = @manager.bot
      @priority = nil

      @botmodule_triggers = Array.new

      @handler = MessageMapper.new(self)
      @registry = @bot.registry_factory.create(@bot.path, self.class.to_s.gsub(/^.*::/, ''))

      @manager.add_botmodule(self)
      @plugin_path = @manager.next_plugin_path
      if self.respond_to?('set_language')
        self.set_language(@bot.lang.language)
      end
    end

    # Changing the value of @priority directly will cause problems,
    # Please use priority=.
    def priority
      @priority ||= 1
    end

    # Returns the symbol :BotModule
    def botmodule_class
      :BotModule
    end

    # Method called to flush the registry, thus ensuring that the botmodule's permanent
    # data is committed to disk
    #
    def flush_registry
      # debug "Flushing #{@registry}"
      @registry.flush
    end


    # Method called to cleanup before the plugin is unloaded. If you overload
    # this method to handle additional cleanup tasks, remember to call super()
    # so that the default cleanup actions are taken care of as well.
    #
    def cleanup
      # debug "Closing #{@registry}"
      @registry.close
    end

    # Handle an Irc::PrivMessage for which this BotModule has a map. The method
    # is called automatically and there is usually no need to call it
    # explicitly.
    #
    def handle(m)
      @handler.handle(m)
    end

    # Signal to other BotModules that an even happened.
    #
    def call_event(ev, *args)
      @bot.plugins.delegate('event_' + ev.to_s.gsub(/[^\w\?!]+/, '_'), *(args.push Hash.new))
    end

    # call-seq: map(template, options)
    #
    # This is the preferred way to register the BotModule so that it
    # responds to appropriately-formed messages on Irc.
    #
    def map(*args)
      do_map(false, *args)
    end

    # call-seq: map!(template, options)
    #
    # This is the same as map but doesn't register the new command
    # as an alternative name for the plugin.
    #
    def map!(*args)
      do_map(true, *args)
    end

    # Auxiliary method called by #map and #map!
    def do_map(silent, *args)
      @handler.map(self, *args)
      # register this map
      map = @handler.last
      name = map.items[0]
      self.register name, :auth => nil, :hidden => silent
      @manager.register_map(self, map)
      unless self.respond_to?('privmsg')
        def self.privmsg(m) #:nodoc:
          handle(m)
        end
      end
    end

    # Sets the default auth for command path _cmd_ to _val_ on channel _chan_:
    # usually _chan_ is either "*" for everywhere, public and private (in which
    # case it can be omitted) or "?" for private communications
    #
    def default_auth(cmd, val, chan="*")
      case cmd
      when "*", ""
        c = nil
      else
        c = cmd
      end
      Auth::defaultbotuser.set_default_permission(propose_default_path(c), val)
    end

    # Gets the default command path which would be given to command _cmd_
    def propose_default_path(cmd)
      [name, cmd].compact.join("::")
    end

    # Return an identifier for this plugin, defaults to a list of the message
    # prefixes handled (used for error messages etc)
    def name
      self.class.to_s.downcase.sub(/^#<module:.*?>::/,"").sub(/(plugin|module)?$/,"")
    end

    # Just calls name
    def to_s
      name
    end

    # Intern the name
    def to_sym
      self.name.to_sym
    end

    # Return a help string for your module. For complex modules, you may wish
    # to break your help into topics, and return a list of available topics if
    # +topic+ is nil. +plugin+ is passed containing the matching prefix for
    # this message - if your plugin handles multiple prefixes, make sure you
    # return the correct help for the prefix requested
    def help(plugin, topic)
      "no help"
    end

    # Register the plugin as a handler for messages prefixed _cmd_.
    #
    # This can be called multiple times for a plugin to handle multiple message
    # prefixes.
    #
    # This command is now superseded by the #map() command, which should be used
    # instead whenever possible.
    #
    def register(cmd, opts={})
      raise ArgumentError, "Second argument must be a hash!" unless opts.kind_of?(Hash)
      who = @manager.who_handles?(cmd)
      if who
        raise "Command #{cmd} is already handled by #{who.botmodule_class} #{who}" if who != self
        return
      end
      if opts.has_key?(:auth)
        @manager.register(self, cmd, opts[:auth])
      else
        @manager.register(self, cmd, propose_default_path(cmd))
      end
      @botmodule_triggers << cmd unless opts.fetch(:hidden, false)
    end

    # Default usage method provided as a utility for simple plugins. The
    # MessageMapper uses 'usage' as its default fallback method.
    #
    def usage(m, params = {})
      if params[:failures].respond_to? :find
        friendly = params[:failures].find do |f|
          f.kind_of? MessageMapper::FriendlyFailure
        end
        if friendly
          m.reply friendly.friendly
          return
        end
      end
      m.reply(_("incorrect usage, ask for help using '%{command}'") % {:command => "#{@bot.nick}: help #{m.plugin}"})
    end

    # Define the priority of the module.  During event delegation, lower
    # priority modules will be called first.  Default priority is 1
    def priority=(prio)
      if @priority != prio
        @priority = prio
        @bot.plugins.mark_priorities_dirty
      end
    end

    # Directory name to be joined to the botclass to access data files. By
    # default this is the plugin name itself, but may be overridden, for
    # example by plugins that share their datafiles or for backwards
    # compatibility
    def dirname
      name
    end

    # Filename for a datafile built joining the botclass, plugin dirname and
    # actual file name
    def datafile(*fname)
      @bot.path dirname, *fname
    end
  end

  # A CoreBotModule is a BotModule that provides core functionality.
  #
  # This class should not be used by user plugins, as it's reserved for system
  # plugins such as the ones that handle authentication, configuration and basic
  # functionality.
  #
  class CoreBotModule < BotModule
    def botmodule_class
      :CoreBotModule
    end
  end

  # A Plugin is a BotModule that provides additional functionality.
  #
  # A user-defined plugin should subclass this, and then define any of the
  # methods described in the documentation for BotModule to handle interaction
  # with Irc events.
  #
  class Plugin < BotModule
    def botmodule_class
      :Plugin
    end
  end

  # Singleton to manage multiple plugins and delegate messages to them for
  # handling
  class PluginManagerClass
    include Singleton
    attr_reader :bot
    attr_reader :botmodules
    attr_reader :maps

    attr_reader :core_module_dirs
    attr_reader :plugin_dirs
    attr_reader :next_plugin_path

    # This is the list of patterns commonly delegated to plugins.
    # A fast delegation lookup is enabled for them.
    DEFAULT_DELEGATE_PATTERNS = %r{^(?:
      connect|names|nick|
      listen|ctcp_listen|privmsg|unreplied|
      kick|join|part|quit|
      save|cleanup|flush_registry|
      set_.*|event_.*
    )$}x

    def initialize
      @botmodules = {
        :CoreBotModule => [],
        :Plugin => []
      }

      @names_hash = Hash.new
      @commandmappers = Hash.new
      @maps = Hash.new

      # modules will be sorted on first delegate call
      @sorted_modules = nil

      @delegate_list = Hash.new { |h, k|
        h[k] = Array.new
      }

      @core_module_dirs = []
      @plugin_dirs = []

      @failed = Array.new
      @ignored = Array.new

      bot_associate(nil)
    end

    def inspect
      ret = self.to_s[0..-2]
      ret << ' corebotmodules='
      ret << @botmodules[:CoreBotModule].map { |m|
        m.name
      }.inspect
      ret << ' plugins='
      ret << @botmodules[:Plugin].map { |m|
        m.name
      }.inspect
      ret << ">"
    end

    # Reset lists of botmodules
    #
    # :botmodule ::
    #   optional instance of a botmodule to remove from the lists
    def reset_botmodule_lists(botmodule=nil)
      if botmodule
        # deletes only references of the botmodule
        @botmodules[:CoreBotModule].delete botmodule
        @botmodules[:Plugin].delete botmodule
        @names_hash.delete_if {|key, value| value == botmodule}
        @commandmappers.delete_if {|key, value| value[:botmodule] == botmodule }
        @delegate_list.each_pair { |cmd, list|
          list.delete botmodule
        }
        @delegate_list.delete_if {|key, value| value.empty?}
        @maps.delete_if {|key, value| value[:botmodule] == botmodule }
        @failures_shown = false
      else
        @botmodules[:CoreBotModule].clear
        @botmodules[:Plugin].clear
        @names_hash.clear
        @commandmappers.clear
        @delegate_list.clear
        @maps.clear
        @failures_shown = false
      end
      mark_priorities_dirty
    end

    # Associate with bot _bot_
    def bot_associate(bot)
      reset_botmodule_lists
      @bot = bot
    end

    # Returns the botmodule with the given _name_
    def [](name)
      return if not name
      @names_hash[name.to_sym]
    end

    # Returns +true+ if a botmodule named _name_ exists.
    def has_key?(name)
      return if not name
      @names_hash.has_key?(name.to_sym)
    end

    # Returns +true+ if _cmd_ has already been registered as a command
    def who_handles?(cmd)
      return nil unless @commandmappers.has_key?(cmd.to_sym)
      return @commandmappers[cmd.to_sym][:botmodule]
    end

    # Registers botmodule _botmodule_ with command _cmd_ and command path _auth_path_
    def register(botmodule, cmd, auth_path)
      raise TypeError, "First argument #{botmodule.inspect} is not of class BotModule" unless botmodule.kind_of?(BotModule)
      @commandmappers[cmd.to_sym] = {:botmodule => botmodule, :auth => auth_path}
    end

    # Registers botmodule _botmodule_ with map _map_. This adds the map to the #maps hash
    # which has three keys:
    #
    # botmodule:: the associated botmodule
    # auth:: an array of auth keys checked by the map; the first is the full_auth_path of the map
    # map:: the actual MessageTemplate object
    #
    #
    def register_map(botmodule, map)
      raise TypeError, "First argument #{botmodule.inspect} is not of class BotModule" unless botmodule.kind_of?(BotModule)
      @maps[map.template] = { :botmodule => botmodule, :auth => [map.options[:full_auth_path]], :map => map }
    end

    def add_botmodule(botmodule)
      raise TypeError, "Argument #{botmodule.inspect} is not of class BotModule" unless botmodule.kind_of?(BotModule)
      kl = botmodule.botmodule_class
      if @names_hash.has_key?(botmodule.to_sym)
        case self[botmodule].botmodule_class
        when kl
          raise "#{kl} #{botmodule} already registered!"
        else
          raise "#{self[botmodule].botmodule_class} #{botmodule} already registered, cannot re-register as #{kl}"
        end
      end
      @botmodules[kl] << botmodule
      @names_hash[botmodule.to_sym] = botmodule
      # add itself to the delegate list for the fast-delegation
      # of methods like cleanup or privmsg, etc..
      botmodule.methods.grep(DEFAULT_DELEGATE_PATTERNS).each { |m|
        @delegate_list[m.intern] << botmodule
      }
      mark_priorities_dirty
    end

    # Returns an array of the loaded plugins
    def core_modules
      @botmodules[:CoreBotModule]
    end

    # Returns an array of the loaded plugins
    def plugins
      @botmodules[:Plugin]
    end

    # Returns a hash of the registered message prefixes and associated
    # plugins
    def commands
      @commandmappers
    end

    # Tells the PluginManager that the next time it delegates an event, it
    # should sort the modules by priority
    def mark_priorities_dirty
      @sorted_modules = nil
    end

    # Makes a string of error _err_ by adding text _str_
    def report_error(str, err)
      ([str, err.inspect] + err.backtrace).join("\n")
    end

    def get_plugin(name)
      plugins.find { |plugin| plugin.name == name }
    end

    # This method is the one that actually loads a module from the
    # file _fname_
    #
    # _desc_ is a simple description of what we are loading
    # (plugin/botmodule/whatever) for error reporting
    #
    # It returns the Symbol :loaded on success, and an Exception
    # on failure
    #
    def load_botmodule_file(fname, desc=nil)
      # create a new, anonymous module to "house" the plugin
      # the idea here is to prevent namespace pollution. perhaps there
      # is another way?
      plugin_module = Module.new
      
      # each plugin uses its own textdomain, we bind it automatically here
      bindtextdomain_to(plugin_module, "rbot-#{File.basename(fname, '.rb')}")

      desc = desc.to_s + " " if desc

      begin
        plugin_string = IO.read(fname)
        debug "loading #{desc}#{fname}"

        # set path of the plugin that will be loaded next (see BotModule#initialize)
        @next_plugin_path = File.dirname fname

        plugin_module.module_eval(plugin_string, fname)

        @next_plugin_path = nil

        return :loaded
      rescue Exception => err
        # rescue Irc::PingError, StandardError, NameError, LoadError, SyntaxError => err
        error report_error("#{desc}#{fname} load failed", err)
        bt = err.backtrace.select { |line|
          line.match(/^(\(eval\)|#{fname}):\d+/)
        }
        bt.map! { |el|
          el.gsub(/^\(eval\)(:\d+)(:in `.*')?(:.*)?/) { |m|
            "#{fname}#{$1}#{$3}"
          }
        }
        msg = err.to_s.gsub(/^\(eval\)(:\d+)(:in `.*')?(:.*)?/) { |m|
          "#{fname}#{$1}#{$3}"
        }
        msg.gsub!(fname, File.basename(fname))
        begin
          newerr = err.class.new(msg)
        rescue ArgumentError => aerr_in_err
          # Somebody should hang the ActiveSupport developers by their balls
          # with barbed wire. Their MissingSourceFile extension to LoadError
          # _expects_ a second argument, breaking the usual Exception interface
          # (instead, the smart thing to do would have been to make the second
          # parameter optional and run the code in the from_message method if
          # it was missing).
          # Anyway, we try to cope with this in the simplest possible way. On
          # the upside, this new block can be extended to handle other similar
          # idiotic approaches
          if err.class.respond_to? :from_message
            newerr = err.class.from_message(msg)
          elsif ([:file, :line, :column, :offset, :problem, :context] & err.methods).length == 6
            # Another ‘brillian’ overload, this time from Psych::SyntaxError
            # In this case we'll just leave the message as-is
            newerr = err.dup
          else
            raise aerr_in_err
          end
        rescue NoMethodError => nmerr_in_err
          # Another braindead extension to StandardError, OAuth2::Error,
          # doesn't get a string as message, but a response
          if err.respond_to? :response
            newerr = err.class.new(err.response)
          else
            raise nmerr_in_err
          end
        end
        newerr.set_backtrace(bt)
        return newerr
      end
    end

    # add one or more directories to the list of directories to
    # load core modules from
    def add_core_module_dir(*dirlist)
      @core_module_dirs += dirlist
      debug "Core module loading paths: #{@core_module_dirs.join(', ')}"
    end

    # add one or more directories to the list of directories to
    # load plugins from
    def add_plugin_dir(*dirlist)
      @plugin_dirs += dirlist
      debug "Plugin loading paths: #{@plugin_dirs.join(', ')}"
    end

    def clear_botmodule_dirs
      @core_module_dirs.clear
      @plugin_dirs.clear
      debug "Core module and plugin loading paths cleared"
    end

    def scan_botmodules(opts={})
      type = opts[:type]
      processed = Hash.new

      case type
      when :core
        dirs = @core_module_dirs
      when :plugins
        dirs = @plugin_dirs

        @bot.config['plugins.blacklist'].each { |p|
          pn = p + ".rb"
          processed[pn.intern] = :blacklisted
        }

        whitelist = @bot.config['plugins.whitelist'].map { |p|
          p + ".rb"
        }
      end

      dirs.each do |dir|
        next unless FileTest.directory?(dir)
        d = Dir.new(dir)
        d.sort.each do |file|
          next unless file =~ /\.rb$/
          next if file =~ /^\./

          case type
          when :plugins
            if !whitelist.empty? && !whitelist.include?(file)
              @ignored << {:name => file, :dir => dir, :reason => :"not whitelisted" }
              next
            elsif processed.has_key?(file.intern)
              @ignored << {:name => file, :dir => dir, :reason => processed[file.intern]}
              next
            end

            if(file =~ /^(.+\.rb)\.disabled$/)
              # GB: Do we want to do this? This means that a disabled plugin in a directory
              #     will disable in all subsequent directories. This was probably meant
              #     to be used before plugins.blacklist was implemented, so I think
              #     we don't need this anymore
              processed[$1.intern] = :disabled
              @ignored << {:name => $1, :dir => dir, :reason => processed[$1.intern]}
              next
            end
          end

          begin
            did_it = load_botmodule_file("#{dir}/#{file}", "plugin")
          rescue Exception => e
            error e
            did_it = e
          end

          case did_it
          when Symbol
            processed[file.intern] = did_it
          when Exception
            @failed << { :name => file, :dir => dir, :reason => did_it }
          end
        end
      end
    end

    # load plugins from pre-assigned list of directories
    def scan
      @failed.clear
      @ignored.clear
      @delegate_list.clear

      scan_botmodules(:type => :core)
      scan_botmodules(:type => :plugins)

      debug "finished loading plugins: #{status(true)}"
      mark_priorities_dirty
    end

    # call the save method for each active plugin
    #
    # :botmodule ::
    #   optional instance of a botmodule to save
    def save(botmodule=nil)
      if botmodule
        botmodule.flush_registry
        botmodule.save if botmodule.respond_to? 'save'
      else
        delegate 'flush_registry'
        delegate 'save'
      end
    end

    # call the cleanup method for each active plugin
    #
    # :botmodule ::
    #   optional instance of a botmodule to cleanup
    def cleanup(botmodule=nil)
      if botmodule
        botmodule.cleanup
      else
        delegate 'cleanup'
      end
      reset_botmodule_lists(botmodule)
    end

    # drops botmodules and rescan botmodules on disk
    # calls save and cleanup for each botmodule before dropping them
    # a optional _botmodule_ argument might specify a botmodule 
    # instance that should be reloaded
    #
    # :botmodule ::
    #   instance of the botmodule to rescan
    def rescan(botmodule=nil)
      save(botmodule)
      cleanup(botmodule)
      if botmodule
        @failed.clear
        @ignored.clear
        filename = where_is(botmodule.class)
        err = load_botmodule_file(filename, "plugin")
        if err.is_a? Exception
          @failed << { :name => botmodule.to_s,
                       :dir => File.dirname(filename), :reason => err }
        end
      else
        scan
      end
    end

    def status(short=false)
      output = []
      if self.core_length > 0
        if short
          output << n_("%{count} core module loaded", "%{count} core modules loaded",
                    self.core_length) % {:count => self.core_length}
        else
          output <<  n_("%{count} core module: %{list}",
                     "%{count} core modules: %{list}", self.core_length) %
                     { :count => self.core_length,
                       :list => core_modules.collect{ |p| p.name}.sort.join(", ") }
        end
      else
        output << _("no core botmodules loaded")
      end
      # Active plugins first
      if(self.length > 0)
        if short
          output << n_("%{count} plugin loaded", "%{count} plugins loaded",
                       self.length) % {:count => self.length}
        else
          output << n_("%{count} plugin: %{list}",
                       "%{count} plugins: %{list}", self.length) %
                   { :count => self.length,
                     :list => plugins.collect{ |p| p.name}.sort.join(", ") }
        end
      else
        output << "no plugins active"
      end
      # Ignored plugins next
      unless @ignored.empty? or @failures_shown
        if short
          output << n_("%{highlight}%{count} plugin ignored%{highlight}",
                       "%{highlight}%{count} plugins ignored%{highlight}",
                       @ignored.length) %
                    { :count => @ignored.length, :highlight => Underline }
        else
          output << n_("%{highlight}%{count} plugin ignored%{highlight}: use %{bold}%{command}%{bold} to see why",
                       "%{highlight}%{count} plugins ignored%{highlight}: use %{bold}%{command}%{bold} to see why",
                       @ignored.length) %
                    { :count => @ignored.length, :highlight => Underline,
                      :bold => Bold, :command => "help ignored plugins"}
        end
      end
      # Failed plugins next
      unless @failed.empty? or @failures_shown
        if short
          output << n_("%{highlight}%{count} plugin failed to load%{highlight}",
                       "%{highlight}%{count} plugins failed to load%{highlight}",
                       @failed.length) %
                    { :count => @failed.length, :highlight => Reverse }
        else
          output << n_("%{highlight}%{count} plugin failed to load%{highlight}: use %{bold}%{command}%{bold} to see why",
                       "%{highlight}%{count} plugins failed to load%{highlight}: use %{bold}%{command}%{bold} to see why",
                       @failed.length) %
                    { :count => @failed.length, :highlight => Reverse,
                      :bold => Bold, :command => "help failed plugins"}
        end
      end
      output.join '; '
    end

    # returns the last logged failure (if present) of a botmodule
    #
    # :name ::
    #   name of the botmodule
    def botmodule_failure(name)
      failure = @failed.find { |f| f[:name] == name }
      if failure
        "%{exception}: %{reason}" % {
          :exception => failure[:reason].class,
          :reason => failure[:reason]
        }
      end
    end

    # return list of help topics (plugin names)
    def helptopics
      rv = status
      @failures_shown = true
      rv
    end

    def length
      plugins.length
    end

    def core_length
      core_modules.length
    end

    # return help for +topic+ (call associated plugin's help method)
    def help(topic = '')
      case topic
      when /fail(?:ed)?\s*plugins?.*(trace(?:back)?s?)?/
        # debug "Failures: #{@failed.inspect}"
        return _("no plugins failed to load") if @failed.empty?
        return @failed.collect { |p|
          _('%{highlight}%{plugin}%{highlight} in %{dir} failed with error %{exception}: %{reason}') % {
              :highlight => Bold, :plugin => p[:name], :dir => p[:dir],
              :exception => p[:reason].class, :reason => p[:reason],
          } + if $1 && !p[:reason].backtrace.empty?
                _('at %{backtrace}') % {:backtrace => p[:reason].backtrace.join(', ')}
              else
                ''
              end
        }.join("\n")
      when /ignored?\s*plugins?/
        return _('no plugins were ignored') if @ignored.empty?

        tmp = Hash.new
        @ignored.each do |p|
          reason = p[:loaded] ? _('overruled by previous') : _(p[:reason].to_s)
          ((tmp[p[:dir]] ||= Hash.new)[reason] ||= Array.new).push(p[:name])
        end

        return tmp.map do |dir, reasons|
          # FIXME get rid of these string concatenations to make gettext easier
          s = reasons.map { |r, list|
            list.map { |_| _.sub(/\.rb$/, '') }.join(', ') + " (#{r})"
          }.join('; ')
          "in #{dir}: #{s}"
        end.join('; ')
      when /^(\S+)\s*(.*)$/
        key = $1
        params = $2

        # Let's see if we can match a plugin by the given name
        (core_modules + plugins).each { |p|
          next unless p.name == key
          begin
            return p.help(key, params)
          rescue Exception => err
            #rescue Irc::PingError, StandardError, NameError, SyntaxError => err
            error report_error("#{p.botmodule_class} #{p.name} help() failed:", err)
          end
        }

        # Nope, let's see if it's a command, and ask for help at the corresponding botmodule
        k = key.to_sym
        if commands.has_key?(k)
          p = commands[k][:botmodule]
          begin
            return p.help(key, params)
          rescue Exception => err
            #rescue Irc::PingError, StandardError, NameError, SyntaxError => err
            error report_error("#{p.botmodule_class} #{p.name} help() failed:", err)
          end
        end
      end
      return false
    end

    def sort_modules
      @sorted_modules = (core_modules + plugins).sort do |a, b|
        a.priority <=> b.priority
      end || []

      @delegate_list.each_value do |list|
        list.sort! {|a,b| a.priority <=> b.priority}
      end
    end

    # delegate(method, [m,] opts={})
    #
    # see if each plugin handles _method_, and if so, call it, passing
    # _m_ as a parameter (if present). BotModules are called in order of
    # priority from lowest to highest.
    #
    # If the passed _m_ is a BasicUserMessage and is marked as #ignored?, it
    # will only be delegated to plugins with negative priority. Conversely, if
    # it's a fake message (see BotModule#fake_message), it will only be
    # delegated to plugins with positive priority.
    #
    # Note that _m_ can also be an exploded Array, but in this case the last
    # element of it cannot be a Hash, or it will be interpreted as the options
    # Hash for delegate itself. The last element can be a subclass of a Hash, though.
    # To be on the safe side, you can add an empty Hash as last parameter for delegate
    # when calling it with an exploded Array:
    #   @bot.plugins.delegate(method, *(args.push Hash.new))
    #
    # Currently supported options are the following:
    # :above ::
    #   if specified, the delegation will only consider plugins with a priority
    #   higher than the specified value
    # :below ::
    #   if specified, the delegation will only consider plugins with a priority
    #   lower than the specified value
    #
    def delegate(method, *args)
      # if the priorities order of the delegate list is dirty,
      # meaning some modules have been added or priorities have been
      # changed, then the delegate list will need to be sorted before
      # delegation.  This should always be true for the first delegation.
      sort_modules unless @sorted_modules

      opts = {}
      opts.merge!(args.pop) if args.last.class == Hash

      m = args.first
      if BasicUserMessage === m
        # ignored messages should not be delegated
        # to plugins with positive priority
        opts[:below] ||= 0 if m.ignored?
        # fake messages should not be delegated
        # to plugins with negative priority
        opts[:above] ||= 0 if m.recurse_depth > 0
      end

      above = opts[:above]
      below = opts[:below]

      # debug "Delegating #{method.inspect}"
      ret = Array.new
      if method.match(DEFAULT_DELEGATE_PATTERNS)
        debug "fast-delegating #{method}"
        m = method.to_sym
        debug "no-one to delegate to" unless @delegate_list.has_key?(m)
        return [] unless @delegate_list.has_key?(m)
        @delegate_list[m].each { |p|
          begin
            prio = p.priority
            unless (above and above >= prio) or (below and below <= prio)
              ret.push p.send(method, *args)
            end
          rescue Exception => err
            raise if err.kind_of?(SystemExit)
            error report_error("#{p.botmodule_class} #{p.name} #{method}() failed:", err)
          end
        }
      else
        debug "slow-delegating #{method}"
        @sorted_modules.each { |p|
          if(p.respond_to? method)
            begin
              # debug "#{p.botmodule_class} #{p.name} responds"
              prio = p.priority
              unless (above and above >= prio) or (below and below <= prio)
                ret.push p.send(method, *args)
              end
            rescue Exception => err
              raise if err.kind_of?(SystemExit)
              error report_error("#{p.botmodule_class} #{p.name} #{method}() failed:", err)
            end
          end
        }
      end
      return ret
      # debug "Finished delegating #{method.inspect}"
    end

    # see if we have a plugin that wants to handle this message, if so, pass
    # it to the plugin and return true, otherwise false
    def privmsg(m)
      debug "Delegating privmsg #{m.inspect} with pluginkey #{m.plugin.inspect}"
      return unless m.plugin
      k = m.plugin.to_sym
      if commands.has_key?(k)
        p = commands[k][:botmodule]
        a = commands[k][:auth]
        # We check here for things that don't check themselves
        # (e.g. mapped things)
        debug "Checking auth ..."
        if a.nil? || @bot.auth.allow?(a, m.source, m.replyto)
          debug "Checking response ..."
          if p.respond_to?("privmsg")
            begin
              debug "#{p.botmodule_class} #{p.name} responds"
              p.privmsg(m)
            rescue Exception => err
              raise if err.kind_of?(SystemExit)
              error report_error("#{p.botmodule_class} #{p.name} privmsg() failed:", err)
            end
            debug "Successfully delegated #{m.inspect}"
            return true
          else
            debug "#{p.botmodule_class} #{p.name} is registered, but it doesn't respond to privmsg()"
          end
        else
          debug "#{p.botmodule_class} #{p.name} is registered, but #{m.source} isn't allowed to call #{m.plugin.inspect} on #{m.replyto}"
        end
      else
        debug "Command #{k} isn't handled"
      end
      return false
    end

    # delegate IRC messages, by delegating 'listen' first, and the actual method
    # afterwards. Delegating 'privmsg' also delegates ctcp_listen and message
    # as appropriate.
    def irc_delegate(method, m)
      delegate('listen', m)
      if method.to_sym == :privmsg
        delegate('ctcp_listen', m) if m.ctcp
        delegate('message', m)
        privmsg(m) if m.address? and not m.ignored?
        delegate('unreplied', m) unless m.replied
      else
        delegate(method, m)
      end
    end
  end

  # Returns the only PluginManagerClass instance
  def Plugins.manager
    return PluginManagerClass.instance
  end

end
end
end
