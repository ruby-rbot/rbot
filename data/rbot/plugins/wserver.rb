class WserverPlugin < Plugin
  def help(plugin, topic = '')
    'wserver <uri> => try and determine what webserver <uri> is using'
  end

  def wserver(m, params)
    redirect_count = 0
    hostname = params[:host].dup
    hostname = "http://#{hostname}" unless hostname =~ /:\/\//
    begin
      if redirect_count > 3
        m.reply 'cowardly refusing to follow more than 3 redirects'
        return
      end

      begin
        uri = URI.parse(hostname)
      rescue URI::InvalidURIError => e
        m.reply "#{hostname} is not a valid URI"
        return
      end

      unless uri
        m.reply "incorrect usage: #{help(m.plugin)}"
        return
      end

      resp = @bot.httputil.head(uri)
      server = resp['Server']
      if server && !server.empty?
        m.reply "#{uri.host} is running #{server}"
      else
        m.reply "couldn't tell what #{uri.host} is running"
      end

      if(resp.code == '302' || resp.code == '301')
        newloc = resp['location']
        newuri = URI.parse(newloc)
        # detect and ignore incorrect redirects (to relative paths etc)
        unless newuri.host.nil?
          if uri.host != newuri.host
            m.reply "#{uri.host} redirects to #{newuri.scheme}://#{newuri.host}"
            raise resp['location']
          end
        end
      end
    rescue Timeout::Error => e
      m.reply "timed out connecting to #{uri.host}:#{uri.port} :("
    rescue RuntimeError => e
      redirect_count += 1
      hostname = e.message
      retry
    rescue StandardError => e
      error e.inspect
      m.reply "couldn't connect to #{uri.host}:#{uri.port} :("
    end
  end
end

plugin = WserverPlugin.new
plugin.map 'wserver :host'
