#-- vim:sw=2:et
#++
#
# :title: Registry: Persistent storage interface and factory
# 
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

module Irc
class Bot

class Registry

  # Dynamically loads the specified registry type library.
  def initialize(format=nil)
    @libpath = File.join(File.dirname(__FILE__), 'registry')
    @format = format
    load File.join(@libpath, @format+'.rb') if format
    # The get_impl method will return all implementations of the
    # abstract accessor interface, since we only ever load one
    # (the configured one) accessor implementation, we can just assume
    # it to be the correct accessor to use.
    accessors = AbstractAccessor.get_impl
    if accessors.length > 1
      warning 'multiple accessor implementations loaded!'
    end
    @accessor_class = accessors.first
  end

  # Returns a list of supported registry database formats.
  def discover
    Dir.glob(File.join(@libpath, '*.rb')).map do |name|
      File.basename(name, File.extname(name))
    end
  end

  # Creates a new Accessor object for the specified database filename.
  def create(path, filename)
    db = @accessor_class.new(File.join(path, 'registry_' + @format, filename.downcase))
    db.optimize
    db
  end

  # Helper method that will return a list of supported registry formats.
  def self.formats
    @@formats ||= Registry.new.discover
  end

  # Will detect tokyocabinet registry location: ~/.rbot/registry/*.tdb
  #  and move it to its new location ~/.rbot/registry_tc/*.tdb
  def migrate_registry_folder(path)
    old_name = File.join(path, 'registry')
    new_name = File.join(path, 'registry_tc')
    if @format == 'tc' and File.exists?(old_name) and
        not File.exists?(new_name) and
        not Dir.glob(File.join(old_name, '*.tdb')).empty?
      File.rename(old_name, new_name)
    end
  end

  # Abstract database accessor (a hash-like interface).
  class AbstractAccessor

    attr_reader :filename

    # lets the user define a recovery procedure in case the Marshal
    # deserialization fails, it might be manually recover data.
    # NOTE: weird legacy stuff, used by markov plugin (WTH?)
    attr_accessor :recovery

    def initialize(filename)
      debug 'init registry accessor for: ' + filename
      @filename = filename
      @name = File.basename filename
      @registry = nil
      @default = nil
      @recovery = nil
      @sub_registries = {}
    end

    def sub_registry(prefix)
      path = File.join(@filename.gsub(/\.[^\/\.]+$/,''), prefix.to_s)
      @sub_registries[path] ||= self.class.new(path)
    end

    # creates the registry / subregistry folders
    def create_folders
      debug 'create folders for: ' + @filename
      dirs = File.dirname(@filename).split("/")
      dirs.length.times { |i|
        dir = dirs[0,i+1].join("/")+"/"
        unless File.exist?(dir)
          Dir.mkdir(dir)
        end
      }
    end

    # Will return true if the database file exists.
    def dbexists?
      File.exists? @filename
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

    # Returned instead of nil if key wasnt found.
    def set_default (default)
      @default = default
    end

    def default
      @default && (@default.dup rescue @default)
    end

    # Opens the database (if not already open) for read/write access.
    def registry
      create_folders unless dbexists?
    end

    # Forces flush/sync the database on disk.
    def flush
      return unless @registry
      # if not supported by the database, close/reopen:
      close
      registry
    end

    # Should optimize/vacuum the database. (if supported)
    def optimize
    end

    # Closes the database.
    def close
      return unless @registry
      @registry.close
      @registry = nil
    end

    # lookup a key in the registry
    def [](key)
      if dbexists? and registry.has_key?(key.to_s)
        return restore(registry[key.to_s])
      else
        return default
      end
    end

    # set a key in the registry
    def []=(key,value)
      registry[key.to_s] = store(value)
    end

    # like Hash#each
    def each(&block)
      return nil unless dbexists?
      registry.each do |key, value|
        block.call(key, restore(value))
      end
    end

    alias each_pair each

    # like Hash#each_key
    def each_key(&block)
      self.each do |key|
        block.call(key)
      end
    end

    # like Hash#each_value
    def each_value(&block)
      self.each do |key, value|
        block.call(value)
      end
    end

    # just like Hash#has_key?
    def has_key?(key)
      return nil unless dbexists?
      return registry.has_key?(key.to_s)
    end

    alias include? has_key?
    alias member? has_key?
    alias key? has_key?

    # just like Hash#has_value?
    def has_value?(value)
      return nil unless dbexists?
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
    # returns the value in success, nil otherwise
    def delete(key)
      return default unless dbexists?
      value = registry.delete(key.to_s)
      if value
        restore(value)
      end
    end

    # returns a list of your keys
    def keys
      return [] unless dbexists?
      return registry.keys
    end

    # Return an array of all associations [key, value] in your namespace
    def to_a
      return [] unless dbexists?
      ret = Array.new
      self.each {|key, value|
        ret << [key, value]
      }
      return ret
    end

    # Return an hash of all associations {key => value} in your namespace
    def to_hash
      return {} unless dbexists?
      ret = Hash.new
      self.each {|key, value|
        ret[key] = value
      }
      return ret
    end

    # empties the registry (restricted to your namespace)
    def clear
      return unless dbexists?
      registry.clear
    end
    alias truncate clear

    # returns an array of the values in your namespace of the registry
    def values
      return [] unless dbexists?
      ret = Array.new
      self.each {|k,v|
        ret << v
      }
      return ret
    end

    # returns the number of keys in your registry namespace
    def length
      return 0 unless dbexists?
      registry.length
    end
    alias size length

    # Returns all classes from the namespace that implement this interface
    def self.get_impl
      ObjectSpace.each_object(Class).select { |klass| klass.ancestors[1] == self }
    end
  end

end # Registry

end # Bot
end # Irc

