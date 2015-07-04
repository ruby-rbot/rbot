#-- vim:sw=2:et
#++
#
# :title: Web service for bot
#
# Author:: Matthias Hecker (apoc@geekosphere.org)
#
# HTTP(S)/json based web service for remote controlling the bot,
# similar to remote but much more portable.
#
# For more info/documentation:
# https://github.com/4poc/rbot/wiki/Web-Service
#

require 'webrick'
require 'webrick/https'
require 'openssl'
require 'cgi'
require 'json'
require 'erb'
require 'ostruct'

module ::Irc
class Bot
    # A WebMessage is a web request and response object combined with helper methods.
    #
    class WebMessage
      # Bot instance
      #
      attr_reader :bot
      # HTTP method (POST, GET, etc.)
      #
      attr_reader :method
      # Request object, a instance of WEBrick::HTTPRequest ({http://www.ruby-doc.org/stdlib-2.0/libdoc/webrick/rdoc/WEBrick/HTTPRequest.html docs})
      #
      attr_reader :req
      # Response object, a instance of WEBrick::HTTPResponse ({http://www.ruby-doc.org/stdlib-2.0/libdoc/webrick/rdoc/WEBrick/HTTPResponse.html docs})
      #
      attr_reader :res
      # Parsed post request parameters.
      #
      attr_reader :post
      # Parsed url parameters.
      #
      attr_reader :args
      # Client IP.
      # 
      attr_reader :client
      # URL Path.
      #
      attr_reader :path
      # The bot user issuing the command.
      #
      attr_reader :source
      def initialize(bot, req, res)
        @bot = bot
        @req = req
        @res = res

        @method = req.request_method
        @post = {}
        if req.body and not req.body.empty?
          @post = parse_query(req.body)
        end
        @args = {}
        if req.query_string and not req.query_string.empty?
          @args = parse_query(req.query_string)
        end
        @client = req.peeraddr[3]

        # login a botuser with http authentication
        WEBrick::HTTPAuth.basic_auth(req, res, 'RBotAuth') { |username, password|
          if username
            botuser = @bot.auth.get_botuser(Auth::BotUser.sanitize_username(username))
            if botuser and botuser.password == password
              @source = botuser
              true
            else
              false
            end
          else
            true # no need to request auth at this point
          end
        }

        @path = req.path

        @load_path = [File.join(Config::datadir, 'web')]
        @load_path += @bot.plugins.core_module_dirs
        @load_path += @bot.plugins.plugin_dirs
      end

      def parse_query(query)
        params = CGI::parse(query)
        params.each_pair do |key, val|
          params[key] = val.last
        end
        params
      end

      # The target of a RemoteMessage
      def target
        @bot
      end

      # Remote messages are always 'private'
      def private?
        true
      end

      # Sends a response with the specified body, status and content type.
      def send_response(body, status, type)
        @res.status = status
        @res['Content-Type'] = type
        @res.body = body
      end

      # Sends a plaintext response
      def send_plaintext(body, status=200)
        send_response(body, status, 'text/plain')
      end

      # Sends a json response
      def send_json(body, status=200)
        send_response(body, status, 'application/json')
      end

      # Sends a html response
      def send_html(body, status=200)
        send_response(body, status, 'text/html')
      end

      # Expands a relative filename to absolute using a list of load paths.
      def get_load_path(filename)
        @load_path.each do |path|
          file = File.join(path, filename) 
          return file if File.exists?(file)
        end
      end

      # Renders a erb template and responds it
      def render(template, args={})
        file = get_load_path template
        if not file
          raise 'template not found: ' + template
        end

        tmpl = ERB.new(IO.read(file))
        ns = OpenStruct.new(args)
        body = tmpl.result(ns.instance_eval { binding })
        send_html(body, 200)
      end
    end

    # works similar to a message mapper but for url paths
    class WebDispatcher
      class WebTemplate
        attr_reader :botmodule, :pattern, :options
        def initialize(botmodule, pattern, options={})
          @botmodule = botmodule
          @pattern = pattern
          @options = options
          set_auth_path(@options)
        end

        def recognize(m)
          message_route = m.path[1..-1].split('/')
          template_route = @pattern[1..-1].split('/')
          params = {}

          debug 'web mapping path %s <-> %s' % [message_route.inspect, template_route.inspect]

          message_route.each do |part|
            tmpl = template_route.shift
            return false if not tmpl

            if tmpl[0] == ':'
              # push part as url path parameter
              params[tmpl[1..-1].to_sym] = part
            elsif tmpl == part
              next
            else
              return false
            end
          end

          debug 'web mapping params is %s' % [params.inspect]

          params
        end

        def set_auth_path(hash)
          if hash.has_key?(:full_auth_path)
            warning "Web route #{@pattern.inspect} in #{@botmodule} sets :full_auth_path, please don't do this"
          else
            pre = @botmodule
            words = @pattern[1..-1].split('/').reject{ |x|
              x == pre || x =~ /^:/ || x =~ /\[|\]/
            }
            if words.empty?
              post = nil
            else
              post = words.first
            end
            if hash.has_key?(:auth_path)
              extra = hash[:auth_path]
              if extra.sub!(/^:/, "")
                pre += "::" + post
                post = nil
              end
              if extra.sub!(/:$/, "")
                if words.length > 1
                  post = [post,words[1]].compact.join("::")
                end
              end
              pre = nil if extra.sub!(/^!/, "")
              post = nil if extra.sub!(/!$/, "")
              extra = nil if extra.empty?
            else
              extra = nil
            end
            hash[:full_auth_path] = [pre,extra,post].compact.join("::")
            debug "Web route #{@pattern} in #{botmodule} will use authPath #{hash[:full_auth_path]}"
          end
        end
      end

      def initialize(bot)
        @bot = bot
        @templates = []
      end

      def map(botmodule, pattern, options={})
        @templates << WebTemplate.new(botmodule.to_s, pattern, options)
        debug 'template route: ' + @templates[-1].inspect
        return @templates.length - 1
      end

      # The unmap method for the RemoteDispatcher nils the template at the given index,
      # therefore effectively removing the mapping
      #
      def unmap(botmodule, index)
        tmpl = @templates[index]
        raise "Botmodule #{botmodule.name} tried to unmap #{tmpl.inspect} that was handled by #{tmpl.botmodule}" unless tmpl.botmodule == botmodule.name
        debug "Unmapping #{tmpl.inspect}"
        @templates[index] = nil
        @templates.clear unless @templates.compact.size > 0
      end

      # Handle a web service request, find matching mapping and dispatch.
      #
      # In case authentication fails, sends a 401 Not Authorized response.
      #
      def handle(m)
        if @templates.empty?
          m.send_plaintext('no routes!', 404)
          return false if @templates.empty?
        end
        failures = []
        @templates.each do |tmpl|
          # Skip this element if it was unmapped
          next unless tmpl
          botmodule = @bot.plugins[tmpl.botmodule]
          params = tmpl.recognize(m)
          if params
            action = tmpl.options[:action]
            unless botmodule.respond_to?(action)
              failures << NoActionFailure.new(tmpl, m)
              next
            end
            # check http method:
            unless not tmpl.options.has_key? :method or tmpl.options[:method] == m.method
              debug 'request method missmatch'
              next
            end
            auth = tmpl.options[:full_auth_path]
            debug "checking auth for #{auth.inspect}"
            # We check for private permission
            if m.bot.auth.permit?(m.source || Auth::defaultbotuser, auth, '?')
              debug "template match found and auth'd: #{action.inspect} #{params.inspect}"
              response = botmodule.send(action, m, params)
              if m.res.sent_size == 0 and m.res.body.empty?
                m.send_json(response.to_json)
              end
              return true
            end
            debug "auth failed for #{auth}"
            # if it's just an auth failure but otherwise the match is good,
            # don't try any more handlers
            m.send_plaintext('Authentication Required!', 401)
            return false
          end
        end
        failures.each {|r|
          debug "#{r.template.inspect} => #{r}"
        }
        debug "no handler found"
        m.send_plaintext('No Handler Found!', 404)
        return false
      end
    end

    # Static web dispatcher instance used internally.
    def web_dispatcher
      if defined? @web_dispatcher
        @web_dispatcher
      else
        @web_dispatcher = WebDispatcher.new(self)
      end
    end

    module Plugins
      # Mixin for plugins that want to provide a web interface of some sort.
      #
      # Plugins include the module and can then use web_map
      # to register a url to handle.
      #
      module WebBotModule
        # The remote_map acts just like the BotModule#map method, except that
        # the map is registered to the @bot's remote_dispatcher. Also, the remote map handle
        # is handled for the cleanup management
        #
        def web_map(*args)
          # stores the handles/indexes for cleanup:
          @web_maps = Array.new unless defined? @web_maps
          @web_maps << @bot.web_dispatcher.map(self, *args)
        end

        # Unregister the remote maps.
        #
        def web_cleanup
          return unless defined? @web_maps
          @web_maps.each { |h|
            @bot.web_dispatcher.unmap(self, h)
          }
          @web_maps.clear
        end

        # Redefine the default cleanup method.
        #
        def cleanup
          super
          web_cleanup
        end
      end

      # And just because I like consistency:
      #
      module WebCoreBotModule
        include WebBotModule
      end

      module WebPlugin
        include WebBotModule
      end
    end
end # Bot
end # Irc

class ::WebServiceUser < Irc::User
  def initialize(str, botuser, opts={})
    super(str, opts)
    @botuser = botuser
    @response = []
  end
  attr_reader :botuser
  attr_accessor :response
end

class DispatchServlet < WEBrick::HTTPServlet::AbstractServlet
  def initialize(server, bot)
    super server
    @bot = bot
  end

  def dispatch(req, res)
    res['Server'] = 'RBot Web Service (http://ruby-rbot.org/)'
    begin
      m = WebMessage.new(@bot, req, res)
      @bot.web_dispatcher.handle m
    rescue WEBrick::HTTPStatus::Unauthorized
      res.status = 401
      res['Content-Type'] = 'text/plain'
      res.body = 'Authentication Required!'
      error 'authentication error (wrong password)'
    rescue
      res.status = 500
      res['Content-Type'] = 'text/plain'
      res.body = "Error: %s\n" % [$!.to_s]
      error 'web dispatch error: ' + $!.to_s
      error $@.join("\n")
    end
  end

  def do_GET(req, res)
    dispatch(req, res)
  end

  def do_POST(req, res)
    dispatch(req, res)
  end
end

class WebServiceModule < CoreBotModule

  include WebCoreBotModule

  Config.register Config::BooleanValue.new('webservice.autostart',
    :default => false,
    :requires_rescan => true,
    :desc => 'Whether the web service should be started automatically')

  Config.register Config::IntegerValue.new('webservice.port',
    :default => 7268,
    :requires_rescan => true,
    :desc => 'Port on which the web service will listen')

  Config.register Config::StringValue.new('webservice.host',
    :default => '127.0.0.1',
    :requires_rescan => true,
    :desc => 'Host the web service will bind on')

  Config.register Config::StringValue.new('webservice.url',
    :default => 'http://127.0.0.1:7268',
    :desc => 'The public URL of the web service.')

  Config.register Config::BooleanValue.new('webservice.ssl',
    :default => false,
    :requires_rescan => true,
    :desc => 'Whether the web server should use SSL (recommended!)')

  Config.register Config::StringValue.new('webservice.ssl_key',
    :default => '~/.rbot/wskey.pem',
    :requires_rescan => true,
    :desc => 'Private key file to use for SSL')

  Config.register Config::StringValue.new('webservice.ssl_cert',
    :default => '~/.rbot/wscert.pem',
    :requires_rescan => true,
    :desc => 'Certificate file to use for SSL')

  Config.register Config::BooleanValue.new('webservice.allow_dispatch',
    :default => true,
    :desc => 'Dispatch normal bot commands, just as a user would through the web service, requires auth for certain commands just like a irc user.')

  def initialize
    super
    @port = @bot.config['webservice.port']
    @host = @bot.config['webservice.host']
    @server = nil
    @bot.webservice = self
    begin
      start_service if @bot.config['webservice.autostart']
    rescue => e
      error "couldn't start web service provider: #{e.inspect}"
    end
  end

  def start_service
    raise "Remote service provider already running" if @server
    opts = {:BindAddress => @host, :Port => @port}
    if @bot.config['webservice.ssl']
      opts.merge! :SSLEnable => true
      cert = File.expand_path @bot.config['webservice.ssl_cert']
      key = File.expand_path @bot.config['webservice.ssl_key']
      if File.exists? cert and File.exists? key
        debug 'using ssl certificate files'
        opts.merge!({
          :SSLCertificate => OpenSSL::X509::Certificate.new(File.read(cert)),
          :SSLPrivateKey => OpenSSL::PKey::RSA.new(File.read(key))
        })
      else
        debug 'using on-the-fly generated ssl certs'
        opts.merge! :SSLCertName => [ %w[CN localhost] ]
        # the problem with this is that it will always use the same
        # serial number which makes this feature pretty much useless.
      end
    end
    # Logging to file in ~/.rbot
    logfile = File.open(@bot.path('webservice.log'), 'a+')
    opts.merge!({
      :Logger => WEBrick::Log.new(logfile),
      :AccessLog => [[logfile, WEBrick::AccessLog::COMBINED_LOG_FORMAT]]
    })
    @server = WEBrick::HTTPServer.new(opts)
    debug 'webservice started: ' + opts.inspect
    @server.mount('/', DispatchServlet, @bot)
    Thread.new { @server.start }
  end

  def stop_service
    @server.shutdown if @server
    @server = nil
  end

  def cleanup
    stop_service
    super
  end

  def handle_start(m, params)
    if @server
      m.reply 'web service already running'
    else
      begin
        start_service
        m.reply 'web service started'
      rescue
        m.reply 'unable to start web service, error: ' + $!.to_s
      end
    end
  end

  def handle_stop(m, params)
    if @server
      stop_service
      m.reply 'web service stopped'
    else
      m.reply 'web service not running'
    end
  end

  def handle_ping(m, params)
    m.send_plaintext("pong\n")
  end

  def handle_dispatch(m, params)
    if not @bot.config['webservice.allow_dispatch']
      m.send_plaintext('dispatch forbidden by configuration', 403)
      return
    end

    command = m.post['command']
    if not m.source
      botuser = Auth::defaultbotuser
    else
      botuser = m.source.botuser
    end
    netmask = '%s!%s@%s' % [botuser.username, botuser.username, m.client]

    debug 'dispatch command: ' + command

    user = WebServiceUser.new(netmask, botuser)
    message = Irc::PrivMessage.new(@bot, nil, user, @bot.myself, command)

    res = @bot.plugins.irc_delegate('privmsg', message)

    if m.req['Accept'] == 'application/json'
      { :reply => user.response }
    else
      m.send_plaintext(user.response.join("\n") + "\n")
    end
  end

end

webservice = WebServiceModule.new

webservice.map 'webservice start',
  :action => 'handle_start',
  :auth_path => ':manage:'

webservice.map 'webservice stop',
  :action => 'handle_stop',
  :auth_path => ':manage:'

webservice.web_map '/ping',
  :action => :handle_ping,
  :auth_path => 'public'

# executes arbitary bot commands
webservice.web_map '/dispatch',
  :action => :handle_dispatch,
  :method => 'POST',
  :auth_path => 'public'

webservice.default_auth('*', false)
webservice.default_auth('public', true)

