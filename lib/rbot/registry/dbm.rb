#-- vim:sw=2:et
#++
#
# The DBM class of the ruby std-lib provides wrappers for Unix-style
# dbm or Database Manager libraries. The exact library used depends
# on how ruby was compiled. Its any of the following: ndbm, bdb,
# gdbm or qdbm.
# DBM API Documentation:
# http://ruby-doc.org/stdlib-2.1.0/libdoc/dbm/rdoc/DBM.html
#
# :title: DB interface

require 'dbm'

module Irc
class Bot
class Registry

  # This class provides persistent storage for plugins via a hash interface.
  # The default mode is an object store, so you can store ruby objects and
  # reference them with hash keys. This is because the default store/restore
  # methods of the plugins' RegistryAccessor are calls to Marshal.dump and
  # Marshal.restore,
  # for example:
  #   blah = Hash.new
  #   blah[:foo] = "fum"
  #   @registry[:blah] = blah
  # then, even after the bot is shut down and disconnected, on the next run you
  # can access the blah object as it was, with:
  #   blah = @registry[:blah]
  # The registry can of course be used to store simple strings, fixnums, etc as
  # well, and should be useful to store or cache plugin data or dynamic plugin
  # configuration.
  #
  # WARNING:
  # in object store mode, don't make the mistake of treating it like a live
  # object, e.g. (using the example above)
  #   @registry[:blah][:foo] = "flump"
  # will NOT modify the object in the registry - remember that Registry#[]
  # returns a Marshal.restore'd object, the object you just modified in place
  # will disappear. You would need to:
  #   blah = @registry[:blah]
  #   blah[:foo] = "flump"
  #   @registry[:blah] = blah
  #
  # If you don't need to store objects, and strictly want a persistant hash of
  # strings, you can override the store/restore methods to suit your needs, for
  # example (in your plugin):
  #   def initialize
  #     class << @registry
  #       def store(val)
  #         val
  #       end
  #       def restore(val)
  #         val
  #       end
  #     end
  #   end
  # Your plugins section of the registry is private, it has its own namespace
  # (derived from the plugin's class name, so change it and lose your data).
  # Calls to registry.each etc, will only iterate over your namespace.
  class Accessor

    attr_accessor :recovery

    # plugins don't call this - a Registry::Accessor is created for them and
    # is accessible via @registry.
    def initialize(bot, name)
      @bot = bot
      @name = name.downcase
      @filename = @bot.path 'registry', @name
      dirs = File.dirname(@filename).split("/")
      dirs.length.times { |i|
        dir = dirs[0,i+1].join("/")+"/"
        unless File.exist?(dir)
          debug "creating subregistry directory #{dir}"
          Dir.mkdir(dir)
        end
      }
      @registry = nil
      @default = nil
      @recovery = nil
      # debug "initializing registry accessor with name #{@name}"
    end

    def registry
      @registry ||= DBM.open(@filename, 0666, DBM::WRCREAT)
    end

    def flush
      return if !@registry
      # ruby dbm has no flush, so we close/reopen :(
      close
      registry
    end

    def close
      return if !@registry
      registry.close
      @registry = nil
    end

    # convert value to string form for storing in the registry
    # defaults to Marshal.dump(val) but you can override this in your module's
    # registry object to use any method you like.
    # For example, if you always just handle strings use:
    #   def store(val)
    #     val
    #   end
    def store(val)
      Marshal.dump(val)
    end

    # restores object from string form, restore(store(val)) must return val.
    # If you override store, you should override restore to reverse the
    # action.
    # For example, if you always just handle strings use:
    #   def restore(val)
    #     val
    #   end
    def restore(val)
      begin
        Marshal.restore(val)
      rescue Exception => e
        error _("failed to restore marshal data for #{val.inspect}, attempting recovery or fallback to default")
        debug e
        if defined? @recovery and @recovery
          begin
            return @recovery.call(val)
          rescue Exception => ee
            error _("marshal recovery failed, trying default")
            debug ee
          end
        end
        return default
      end
    end

    # lookup a key in the registry
    def [](key)
      if registry.has_key?(key.to_s)
        return restore(registry[key.to_s])
      else
        return default
      end
    end

    # set a key in the registry
    def []=(key,value)
      registry[key.to_s] = store(value)
    end

    # set the default value for registry lookups, if the key sought is not
    # found, the default will be returned. The default default (har) is nil.
    def set_default (default)
      @default = default
    end

    def default
      @default && (@default.dup rescue @default)
    end

    # like Hash#each
    def each(&block)
      registry.each_key do |key|
        block.call(key, self[key])
      end
    end

    alias each_pair each

    # like Hash#each_key
    def each_key(&block)
      registry.each_key do |key|
        block.call(key)
      end
    end

    # like Hash#each_value
    def each_value(&block)
      registry.each_key do |key|
        block.call(self[key])
      end
    end

    # just like Hash#has_key?
    def has_key?(key)
      return registry.has_key?(key.to_s)
    end

    alias include? has_key?
    alias member? has_key?
    alias key? has_key?

    # just like Hash#has_both?
    def has_both?(key, value)
      registry.has_key?(key.to_s) and registry.has_value?(store(value))
    end

    # just like Hash#has_value?
    def has_value?(value)
      return registry.has_value?(store(value))
    end

    # just like Hash#index?
    def index(value)
      self.each do |k,v|
        return k if v == value
      end
      return nil
    end

    # delete a key from the registry
    def delete(key)
      return registry.delete(key.to_s)
    end

    # returns a list of your keys
    def keys
      return registry.keys
    end

    # Return an array of all associations [key, value] in your namespace
    def to_a
      ret = Array.new
      registry.each {|key, value|
        ret << [key, restore(value)]
      }
      return ret
    end

    # Return an hash of all associations {key => value} in your namespace
    def to_hash
      ret = Hash.new
      registry.each {|key, value|
        ret[key] = restore(value)
      }
      return ret
    end

    # empties the registry (restricted to your namespace)
    def clear
      registry.clear
    end
    alias truncate clear

    # returns an array of the values in your namespace of the registry
    def values
      ret = Array.new
      self.each {|k,v|
        ret << restore(v)
      }
      return ret
    end

    def sub_registry(prefix)
      return Accessor.new(@bot, @name + "/" + prefix.to_s)
    end

    # returns the number of keys in your registry namespace
    def length
      registry.length
    end
    alias size length
  end

end # Registry
end # Bot
end # Irc

