#-- vim:sw=2:et
#++
#
# :title: Sqlite3 registry implementation
#

require 'sqlite3'

module Irc
class Bot
class Registry

  class SqliteAccessor < AbstractAccessor

    def initialize(filename)
      super filename + '.db'
    end

    def registry
      super
      unless @registry
        @registry = SQLite3::Database.new(@filename)
        begin
          @registry.execute('SELECT COUNT(*) FROM data')
        rescue
          @registry.execute('CREATE TABLE data (key PRIMARY KEY, value)')
        end
      end
      @registry
    end

    def optimize
      return unless @registry
      @registry.execute('VACUUM')
    end

    def [](key)
      if dbexists?
        begin
          value = registry.get_first_row('SELECT value FROM data WHERE key = ?', key.to_s)
          return restore(value.first)
        rescue
          return default
        end
      else
        return default
      end
    end

    def []=(key,value)
      value = SQLite3::Blob.new(store(value))
      if has_key? key
        registry.execute('UPDATE data SET value = ? WHERE key = ?', value, key.to_s)
      else
        registry.execute('INSERT INTO data VALUES (?, ?)', key.to_s, value)
      end
    end

    def each(&block)
      return nil unless dbexists?
      res = registry.execute('SELECT * FROM data')
      res.each do |row|
        key, value = row
        block.call(key, restore(value))
      end
    end

    alias each_pair each

    def has_key?(key)
      return nil unless dbexists?
      res = registry.get_first_row('SELECT COUNT(*) FROM data WHERE key = ?', key.to_s)
      return res.first > 0
    end

    alias include? has_key?
    alias member? has_key?
    alias key? has_key?

    def has_value?(value)
      return nil unless dbexists?
      value = SQLite3::Blob.new(store(value))
      res = registry.get_first_row('SELECT COUNT(*) FROM data WHERE value = ?', value)
      return res.first > 0
    end

    def delete(key)
      return default unless dbexists?
      begin
        value = self[key]
        registry.execute('DELETE FROM data WHERE key = ?', key.to_s)
        value if registry.changes > 0
      rescue
        nil
      end
    end

    # returns a list of your keys
    def keys
      return [] unless dbexists?
      res = registry.execute('SELECT key FROM data')
      res.map { |row| row.first }
    end

    def clear
      return unless dbexists?
      registry.execute('DELETE FROM data')
    end

    alias truncate clear

    # returns the number of keys in your registry namespace
    def length
      return 0 unless dbexists?
      res = registry.get_first_row('SELECT COUNT(key) FROM data')
      res.first
    end

    alias size length

  end

end # Registry
end # Bot
end # Irc

