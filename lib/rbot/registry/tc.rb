#-- vim:sw=2:et
#++
#
# :title: TokyoCabinet B+Tree registry implementation
#
# TokyoCabinet is a "modern implementation of the DBM".
# http://fallabs.com/tokyocabinet/
#

require 'tokyocabinet'

module Irc
class Bot
class Registry

  class TokyoCabinetAccessor < AbstractAccessor

    def initialize(filename)
      super filename + '.tdb'
    end

    def registry
      super
      unless @registry
        @registry = TokyoCabinet::BDB.new
        @registry.open(@filename, 
          TokyoCabinet::BDB::OREADER | 
          TokyoCabinet::BDB::OCREAT | 
          TokyoCabinet::BDB::OWRITER)
      end
      @registry
    end

    def flush
      return unless @registry
      @registry.sync
    end

    def optimize
      return unless @registry
      @registry.optimize
    end

    def delete(key)
      return default unless dbexists?
      value = self[key]
      registry.delete(key.to_s)
      value # return deleted value if success
    end

  end

end # Registry
end # Bot
end # Irc

