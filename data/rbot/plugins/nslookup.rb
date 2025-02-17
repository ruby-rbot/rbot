class DnsPlugin < Plugin
  require 'resolv'

  def gethostname(address)
    Resolv.getname(address)
  end

  def getaddresses(name)
    Resolv.getaddresses(name)
  end

  def help(plugin, topic = '')
    'dns <hostname|ip> => show local resolution results for hostname or ip address'
  end

  def name_to_ip(m, params)
    a = getaddresses(params[:host])
    if !a.empty?
      m.reply "#{m.params}: #{a.join(', ')}"
    else
      m.reply "#{params[:host]}: not found"
    end
  rescue StandardError => e
    m.reply "#{params[:host]}: not found"
  end

  def ip_to_name(m, params)
    a = gethostname(params[:ip])
    m.reply "#{m.params}: #{a}" if a
  rescue StandardError => e
    m.reply "#{params[:ip]}: not found (does not reverse resolve)"
  end
end

plugin = DnsPlugin.new
plugin.map 'dns :ip', :action => 'ip_to_name', :thread => true,
                      :requirements => { :ip => /^\d+\.\d+\.\d+\.\d+$/ }
plugin.map 'dns :host', :action => 'name_to_ip', :thread => true
