class PointsPlugin < Plugin
  def initialize
    super

    # this plugin only wants to store ints!
    class << @registry
      def store(val)
        val.to_i
      end
      def restore(val)
        val.to_i
      end
    end
    @registry.set_default(0)

    # import if old file format found
    oldpoints = @bot.path 'points.rbot'
    if File.exist? oldpoints
      log "importing old points data"
      IO.foreach(oldpoints) do |line|
        if(line =~ /^(\S+)<=>([\d-]+)$/)
          item = $1
          points = $2.to_i
          @registry[item] = points
        end
      end
      File.delete oldpoints
    end
  end

  def stats(m, params)
    if (@registry.length)
      max = @registry.values.max || "zero"
      min = @registry.values.min || "zero"
      best = @registry.to_hash.key(max) || "nobody"
      worst = @registry.to_hash.key(min) || "nobody"
      m.reply "#{@registry.length} items. Best: #{best} (#{max}); Worst: #{worst} (#{min})"
    end
  end

  def dump(m, params)
    if (@registry.length)
      msg = "Points dump: "
      msg << @registry.to_hash.sort_by { |k, v| v }.reverse.
                       map { |k,v| "#{k}: #{v}" }.
                       join(", ")
      m.reply msg
    else
      m.reply "nobody has any points yet!"
    end
  end

  def points(m, params)
    thing = params[:key]
    thing = m.sourcenick unless thing
    thing = thing.to_s
    points = @registry[thing]
    if(points != 0)
      m.reply "points for #{thing}: #{@registry[thing]}"
    else
      m.reply "#{thing} has zero points"
    end
  end

  def setpoints(m, params)
    thing = (params[:key] || m.sourcenick).to_s
    @registry[thing] = params[:val].to_i
    points(m, params)
  end

  def help(plugin, topic="")
    "points module: Keeps track of internet points, infusing your pointless life with meaning. Listens to everyone's chat. <thing>++/<thing>-- => increase/decrease points for <thing>, points for <thing>? => show points for <thing>, pointstats => show best/worst, pointsdump => show everyone's points. Points are a community rating system - only in-channel messages can affect points and you cannot adjust your own."
  end

  def message(m)
    return unless m.public? && m.message.match(/\+\+|--/)
    arg = nil
    op = nil
    ac = Hash.new
    m.message.split.each_with_index do |tok, i|
      # ignore preceeding +/-
      if op && arg.nil?
        op = nil
      end
      tok.sub!(/[:,]$/, '') if i == 0
      catch :me_if_you_can do
        if m.channel.users[tok].nil?
          if tok =~ /^(.*[^-].*)(?:--)$/
            op, arg = '--', $1
            next
          elsif tok =~ /^(.*[^+].*)(?:\+\+)$/
            op, arg = '++', $1
            next
          end
        end

        if (tok =~ /^--+$/) || (tok =~ /^\+\++$/)
          op = tok.slice(0, 2)
        else
          arg = tok
        end
      end # catch

      if op && arg
        ac[arg] ||= 0
        ac[arg] += (op == '--' ? -1 : 1) unless arg.downcase == m.sourcenick.downcase
        op = arg = nil
      end
    end

    ac.each do |k, v|
      next if v == 0 or /--|\+\+/.match(k)
      # strip invisible formatting characters like bold or color codes
      k = k.gsub(FormattingRx, '')
      @registry[k] += (v > 0 ? 1 : -1)
      m.reply @bot.lang.get("thanks") if k == @bot.nick && v > 0
      m.reply "#{k} now has #{@registry[k]} points!"
    end
  end
end

plugin = PointsPlugin.new

plugin.default_auth( 'edit', false )

plugin.map 'pointstats', :action => 'stats'
plugin.map 'points :key', :defaults => {:key => false}
plugin.map 'setpoints :key :val', :defaults => {:key => false}, :requirements => {:val => /^-?\d+$/}, :auth_path => 'edit::set!'
plugin.map 'points for :key'
plugin.map 'pointsdump', :action => 'dump'
