# encoding: UTF-8
#-- vim:sw=2:et
#++
#
# :title: rbot logger

require 'logger'
require 'thread'
require 'singleton'

module Irc
class Bot

  class LoggerManager
    include Singleton

    def initialize
      @dateformat = "%Y/%m/%d %H:%M:%S"

      @logger = Logger.new(STDERR)
      @logger.datetime_format = @dateformat
      @logger.level = Logger::Severity::DEBUG
      @file_logger = nil

      @queue = Queue.new
      @thread = start_thread
    end

    def set_logfile(filename, keep, max_size)
      @file_logger = Logger.new(filename, keep, max_size*1024*1024)
      @file_logger.datetime_format = @dateformat
    end

    def set_level(level)
      @logger.level = level
      if @file_logger
        @file_logger.level = level
      end
    end

    def sync_log(severity, message = nil, progname = nil)
      @logger.add(severity, message, progname)
      if @file_logger
        @file_logger.add(severity, message, progname)
      end
    end

    def async_log(severity, message=nil, who_pos=1)
      unless @thread
        STDERR.puts('logger thread already destroyed, cannot log message!')
      end

      call_stack = caller
      if call_stack.length > who_pos
        who = call_stack[who_pos].sub(%r{(?:.+)/([^/]+):(\d+)(:in .*)?}) { "#{$1}:#{$2}#{$3}" }
      else
        who = "(unknown)"
      end
      # Output each line. To distinguish between separate messages and multi-line
      # messages originating at the same time, we blank #{who} after the first message
      # is output.
      # Also, we output strings as-is but for other objects we use pretty_inspect
      message = message.kind_of?(String) ? message : (message.pretty_inspect rescue '?')
      qmsg = Array.new
      message.each_line { |l|
        qmsg.push [severity, l.chomp, who]
        who = ' ' * who.size
      }
      @queue.push qmsg
    end

    def log_session_start
      if @file_logger
        @file_logger << "\n\n=== session started on #{Time.now.strftime(@dateformat)} ===\n\n"
      end
    end

    def log_session_end
      if @file_logger
        @file_logger << "\n\n=== session ended on #{Time.now.strftime(@dateformat)} ===\n\n"
      end
    end

    def halt_logger
      if @thread and @thread.alive?
        @queue << nil
        @thread.join
        @thread = nil
      end
    end

    private

    def start_thread
      Thread.new do
        lines = nil
        while lines = @queue.pop
          lines.each { |line|
            sync_log(*line)
          }
        end
      end
    end

  end

end
end

def debug(message=nil, who_pos=1)
  Irc::Bot::LoggerManager.instance.async_log(Logger::Severity::DEBUG, message, who_pos)
end

def log(message=nil, who_pos=1)
  Irc::Bot::LoggerManager.instance.async_log(Logger::Severity::INFO, message, who_pos)
end

def warning(message=nil, who_pos=1)
  Irc::Bot::LoggerManager.instance.async_log(Logger::Severity::WARN, message, who_pos)
end

def error(message=nil, who_pos=1)
  Irc::Bot::LoggerManager.instance.async_log(Logger::Severity::ERROR, message, who_pos)
end

def fatal(message=nil, who_pos=1)
  Irc::Bot::LoggerManager.instance.async_log(Logger::Severity::FATAL, message, who_pos)
end
