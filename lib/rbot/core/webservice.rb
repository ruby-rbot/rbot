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

  def do_POST(req, res)
    # NOTE: still wip.
    uri = req.path_info
    post = CGI::parse(req.body)
    ip = req.peeraddr[3]

    command = uri.gsub('/', ' ').strip

    username = post['username'].first
    password = post['password'].first

    botuser = @bot.auth.get_botuser(username)
    netmask = '%s!%s@%s' % [botuser.username, botuser.username, ip]

    if not botuser or botuser.password != password
      raise 'Permission Denied'
    end

    ws_user = WebServiceUser.new(netmask, botuser)
    message = Irc::PrivMessage.new(@bot, nil, ws_user, @bot.myself, command)

    @bot.plugins.irc_delegate('privmsg', message)

    res.status = 200
    res['Content-Type'] = 'text/plain'
    res.body = ws_user.response.join("\n") + "\n"
  end
end

class WebServiceModule < CoreBotModule

  Config.register Config::BooleanValue.new('webservice.autostart',
    :default => false,
    :requires_rescan => true,
    :desc => 'Whether the web service should be started automatically')

  Config.register Config::IntegerValue.new('webservice.port',
    :default => 7260, # that's 'rbot'
    :requires_rescan => true,
    :desc => 'Port on which the web service will listen')

  Config.register Config::StringValue.new('webservice.host',
    :default => '127.0.0.1',
    :requires_rescan => true,
    :desc => 'Host the web service will bind on')

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

  def initialize
    super
    @port = @bot.config['webservice.port']
    @host = @bot.config['webservice.host']
    @server = nil
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
    @server = WEBrick::HTTPServer.new(opts)
    debug 'webservice started: ' + opts.inspect
    @server.mount('/dispatch', DispatchServlet, @bot)
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
    s = ''
    if @server
      s << 'web service already running'
    else
      begin
        start_service
        s << 'web service started'
      rescue
        s << 'unable to start web service, error: ' + $!.to_s
      end
    end
    m.reply s
  end

end

webservice = WebServiceModule.new

webservice.map 'webservice start',
  :action => 'handle_start',
  :auth_path => ':manage:'

webservice.map 'webservice stop',
  :action => 'handle_stop',
  :auth_path => ':manage:'

webservice.default_auth('*', false)

