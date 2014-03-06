$:.unshift File.join(File.dirname(__FILE__), '../lib')

require 'test/unit'
require 'rbot/ircbot'
require 'rbot/registry'

require 'pp'
require 'tmpdir'

class FooObj
  attr_reader :bar
  def initialize(bar)
    @bar = bar
  end
end

module RegistryHashInterfaceTests
  def test_object
    @reg['store'] = {
      :my_obj => FooObj.new(42)
    }

    assert_equal(42, @reg['store'][:my_obj].bar)

    @reg.close
    @reg = open(@tempdir)

    assert_equal(42, @reg['store'][:my_obj].bar)
  end

  def test_default
    @reg.set_default(42)
    assert_equal(42, @reg['not-here'])
    assert_equal(42, @reg.default)
  end

  def test_flush
    # I don't know if there really is a good way to test this:
    big_string = 'A' * (1024 * 512)
    @reg['foo'] = big_string+'a'

    dbfile = @reg.filename
    assert_not_nil(dbfile)
    if not File.exists? dbfile
      # dbm ext. are arbitary
      dbfile = Dir.glob(dbfile+'.*').first
    end
    assert_not_nil(dbfile)

    assert(File.exists?(dbfile), 'expected database to exist')

    size_before = File.size(dbfile)
    @reg['bar'] = big_string
    @reg.flush
    size_after = File.size(dbfile)

    assert(size_before < size_after, 'expected big string to be flushed on disk!')
  end

  def test_optimize
    @reg.optimize
  end

  def test_close
    @reg.close
  end

  def test_getset # [] and []=
    @reg['mykey'] = 'myvalue'
    assert_equal('myvalue', @reg['mykey'],'expected set value')
    @reg['mykey'] = 42
    assert_equal(42, @reg['mykey'], 'expected set value to overwrite')
    @reg[23] = 5
    assert_equal(5, @reg[23], 'expected integer key to respond')
    @reg['myKey'] = 45
    assert_equal(42, @reg['mykey'], 'expected keys tobe case-sensitive')
    assert_equal(45, @reg['myKey'], 'expected keys tobe case-sensitive')
    assert_nil(@reg['not-there'])
  end

  def test_getset_persists
    @reg['mykey'] = 'myvalue'
    @reg['myKey'] = 45
    @reg[23] = 5
    @reg.close
    @reg = open(@tempdir)
    assert_equal('myvalue', @reg['mykey'], 'expected value to persist')
    assert_equal(5, @reg[23], 'expected integer key to persist')

    assert_equal(45, @reg['myKey'], 'expected keys tobe case-sensitive')
    assert_nil(@reg['not-there'])
  end

  def test_each
    @reg['mykey1'] = 'myvalue1'
    @reg['mykey2'] = 'myvalue2'
    @reg['mykey3'] = 'myvalue3'
    resp = {}
    i = 0
    @reg.each do |key, value|
      resp[key] = value
      i += 1
    end
    assert_equal(3, i, 'expected block to yield 3 times')
    assert(resp.has_key? 'mykey1')
    assert(resp.has_key? 'mykey2')
    assert(resp.has_key? 'mykey3')
    assert_equal('myvalue1', resp['mykey1'])
    assert_equal('myvalue2', resp['mykey2'])
    assert_equal('myvalue3', resp['mykey3'])
  end

  def test_each_pair
    @reg['mykey1'] = 'myvalue1'
    @reg['mykey2'] = 'myvalue2'
    @reg['mykey3'] = 'myvalue3'
    resp = {}
    i = 0
    @reg.each_pair do |key, value|
      resp[key] = value
      i += 1
    end
    assert_equal(3, i, 'expected block to yield 3 times')
    assert(resp.has_key? 'mykey1')
    assert(resp.has_key? 'mykey2')
    assert(resp.has_key? 'mykey3')
    assert_equal('myvalue1', resp['mykey1'])
    assert_equal('myvalue2', resp['mykey2'])
    assert_equal('myvalue3', resp['mykey3'])
  end

  def test_each_key
    @reg['mykey1'] = 'myvalue1'
    @reg['mykey2'] = 'myvalue2'
    @reg['mykey3'] = 'myvalue3'
    resp = []
    i = 0
    @reg.each_key do |key|
      resp << key
      i += 1
    end
    assert_equal(3, i, 'expected block to yield 3 times')
    assert(resp.include? 'mykey1')
    assert(resp.include? 'mykey2')
    assert(resp.include? 'mykey3')
  end

  def test_each_value
    @reg['mykey1'] = 'myvalue1'
    @reg['mykey2'] = 'myvalue2'
    @reg['mykey3'] = 'myvalue3'
    resp = []
    i = 0
    @reg.each_value do |value|
      resp << value
      i += 1
    end
    assert_equal(3, i, 'expected block to yield 3 times')
    assert(resp.include? 'myvalue1')
    assert(resp.include? 'myvalue2')
    assert(resp.include? 'myvalue3')
  end

  def test_has_key
    @reg['mykey1'] = 'myvalue1'
    @reg['mykey2'] = 'myvalue2'
    @reg[23] = 5
    assert(@reg.has_key?('mykey1'))
    assert(@reg.has_key?('mykey2'))
    assert(@reg.has_key?(23))
    assert_equal(false, @reg.has_key?('mykey3'))
    assert_equal(false, @reg.has_key?(42))
  end

  def test_has_value
    @reg['mykey1'] = 'myvalue1'
    @reg[23] = 5
    assert(@reg.has_value?('myvalue1'))
    assert(@reg.has_value?(5))
    assert_equal(false, @reg.has_value?('myvalue3'))
    assert_equal(false, @reg.has_value?(10))
  end

  def test_index
    @reg['mykey1'] = 'myvalue1'
    @reg[23] = 5
    assert_equal('mykey1', @reg.index('myvalue1'))
    assert_equal('23', @reg.index(5))
  end

  def test_delete
    @reg['mykey'] = 'myvalue'
    assert_not_nil(@reg['mykey'])
    @reg.delete('mykey')
    assert_nil(@reg['mykey'])
  end

  def test_delete_return
    @reg['mykey'] = 'myvalue'
    assert_equal('myvalue', @reg.delete('mykey'), 'delete should return the deleted value')
    assert_nil(@reg.delete('mykey'))
  end

  def test_to_a
    @reg['mykey1'] = 'myvalue1'
    @reg['mykey2'] = 'myvalue2'
    myhash = {}
    myhash['mykey1'] = 'myvalue1'
    myhash['mykey2'] = 'myvalue2'
    assert_equal(myhash.to_a, @reg.to_a)
  end

  def test_to_hash
    @reg['mykey1'] = 'myvalue1'
    @reg['mykey2'] = 'myvalue2'
    myhash = {}
    myhash['mykey1'] = 'myvalue1'
    myhash['mykey2'] = 'myvalue2'
    assert_equal(myhash.to_hash, @reg.to_hash)
  end

  def test_clear
    @reg['mykey1'] = 'myvalue1'
    @reg['mykey2'] = 'myvalue2'
    assert_not_nil(@reg['mykey1'])
    @reg.clear
    assert_nil(@reg['mykey1'])
  end

  def test_clear_persists
    @reg['mykey1'] = 'myvalue1'
    @reg['mykey2'] = 'myvalue2'
    assert_not_nil(@reg['mykey1'])
    @reg.close
    @reg = open(@tempdir)
    assert_not_nil(@reg['mykey1'])
  end

  def test_values
    @reg['mykey1'] = 'myvalue1'
    @reg['mykey2'] = 'myvalue2'
    myhash = {}
    myhash['mykey1'] = 'myvalue1'
    myhash['mykey2'] = 'myvalue2'
    assert_equal(myhash.values, @reg.values)
  end

  def test_length
    @reg['mykey1'] = 'myvalue1'
    @reg['mykey2'] = 'myvalue2'
    assert_equal(2, @reg.length)
  end
end

module RegistryTestModule
  def setup
    @tempdir = Dir.mktmpdir
    @reg = open(@tempdir)
  end

  def teardown
    @reg.close
    FileUtils.remove_entry @tempdir
  end

  def open(path, filename='testcase')
    puts 'open type: ' + @format
    @registry_class.new(File.join(path, filename))
  end
end

class RegistryDBMTest < Test::Unit::TestCase
  include RegistryTestModule
  include RegistryHashInterfaceTests

  def initialize(o)
    super o
    @format = 'dbm'
    Irc::Bot::Registry.new(@format)
    @registry_class = Irc::Bot::Registry::DBMAccessor
  end
end

class RegistryTCTest < Test::Unit::TestCase
  include RegistryTestModule
  include RegistryHashInterfaceTests

  def initialize(o)
    super o
    @format = 'tc'
    Irc::Bot::Registry.new(@format)
    @registry_class = Irc::Bot::Registry::TokyoCabinetAccessor
  end
end

class RegistryDaybreakTest < Test::Unit::TestCase
  include RegistryTestModule
  include RegistryHashInterfaceTests

  def initialize(o)
    super o
    @format = 'daybreak'
    Irc::Bot::Registry.new(@format)
    @registry_class = Irc::Bot::Registry::DaybreakAccessor
  end
end

class RegistrySqliteTest < Test::Unit::TestCase
  include RegistryTestModule
  include RegistryHashInterfaceTests

  def initialize(o)
    super o
    @format = 'sqlite'
    Irc::Bot::Registry.new(@format)
    @registry_class = Irc::Bot::Registry::SqliteAccessor
  end

  def test_duplicate_keys
    @reg['foo'] = 1
    @reg['foo'] = 2
    res = @reg.registry.execute('select key from data')
    assert res.length == 1
  end
end

