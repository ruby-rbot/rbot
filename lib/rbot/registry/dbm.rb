#-- vim:sw=2:et
#++
#
# :title: DBM registry implementation
#
# DBM is the ruby standard library wrapper module for Unix-style
# dbm libraries. The specific library used depends
# on how ruby was compiled. Its any of the following: ndbm, bdb,
# gdbm or qdbm.
# http://ruby-doc.org/stdlib-2.1.0/libdoc/dbm/rdoc/DBM.html
#

require 'dbm'

module Irc
class Bot
class Registry

  class DBMAccessor < AbstractAccessor

    def registry
      super
      @registry ||= DBM.open(@filename, 0666, DBM::WRCREAT)
    end

    def dbexists?
      not Dir.glob(@filename + '.*').empty?
    end

  end

end # Registry
end # Bot
end # Irc

