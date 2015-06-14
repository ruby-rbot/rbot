# encoding: UTF-8
#-- vim:sw=2:et
#++
#
# :title: journal backend for postgresql

require 'pg'

module Irc
class Bot
module Journal
  module Storage
    class PostgresStorage < AbstractStorage
      def initialize(opts={})
        @uri = opts[:uri] || 'postgresql://localhost/rbot_journal'
        @conn = PG.connect(@uri)
        @version = @conn.exec('SHOW server_version;')[0]['server_version']

        @version.gsub!(/^(\d+\.\d+)$/, '\1.0')
        log 'journal storage: postgresql connected to version: ' + @version
        
        version = @version.split('.')[0,3].join.to_i
        if version < 930
          raise StorageError.new(
            'PostgreSQL Version too old: %s, supported: >= 9.3' % [@version])
        end
        @jsonb = (version >= 940)
        log 'journal storage: no jsonb support, consider upgrading postgres'

        create_table
      end

      def create_table
      end
    end
  end
end # Journal
end # Bot
end # Irc
