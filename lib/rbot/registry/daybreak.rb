#-- vim:sw=2:et
#++
#
# :title: Daybreak registry implementation
#
# Daybreak is a fast in-memory(!!!) database:
# http://propublica.github.io/daybreak/
#

require 'daybreak'

module Irc
class Bot
class Registry

  class DaybreakAccessor < AbstractAccessor

    def initialize(filename)
      super filename + '.db'
    end

    def registry
      super
      @registry ||= Daybreak::DB.new(@filename)
    end

    def flush
      return unless @registry
      @registry.flush
    end

    def optimize
      return unless @registry
      @registry.compact
    end

  end

end # Registry
end # Bot
end # Irc

