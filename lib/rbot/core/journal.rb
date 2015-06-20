#-- vim:sw=2:et
#++
#
# :title: rbot journal management from IRC
#
# Author:: Matthias Hecker (apoc@geekosphere.org)

require 'rbot/journal'

class JournalModule < CoreBotModule

  attr_reader :broker

  include Irc::Bot::Journal

  Config.register Config::StringValue.new('journal.storage',
    :default => nil,
    :requires_rescan => true,
    :desc => 'storage engine used by the journal')
  Config.register Config::StringValue.new('journal.storage.uri',
    :default => nil,
    :requires_rescan => true,
    :desc => 'storage database uri')

  def initialize
    super
    storage = nil
    name = @bot.config['journal.storage']
    uri = @bot.config['journal.storage.uri']
    if name
      storage = Storage.create(name, uri)
    end
    debug 'journal broker starting up...'
    @broker = JournalBroker.new(storage: storage)
  end

  def cleanup
    super
    debug 'journal broker shutting down...'
    @broker.shutdown
    @broker = nil
  end

  def help(plugin, topic='')
    'journal'
  end

end

journal = JournalModule.new
journal.priority = -2

