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

    def enable_console_logger
      @console_logger = Logger.new(STDERR)
      @console_logger.datetime_format = @dateformat
      @console_logger.level = Logger::Severity::DEBUG
    end

    def disable_console_logger
      @console_logger.close if @console_logger
      @console_logger = nil
    end

    def initialize
      @dateformat = "%Y/%m/%d %H:%M:%S"

      enable_console_logger

      @file_logger = nil

      @queue = Queue.new
      start_thread
    end

    def set_logfile(filename, keep, max_size)
      # close previous file logger if present
      @file_logger.close if @file_logger

      @file_logger = Logger.new(filename, keep, max_size*1024*1024)
      @file_logger.datetime_format = @dateformat
      @file_logger.level = @console_logger.level

      # make sure the thread is running, which might be false after a fork
      # (conveniently, we call set_logfile right after the fork)
      start_thread
    end

    def set_level(level)
      @console_logger.level = level if @console_logger
      @file_logger.level = level if @file_logger
    end

    def sync_log(severity, message = nil, progname = nil)
      @console_logger.add(severity, message, progname) if @console_logger
      @file_logger.add(severity, message, progname) if @file_logger
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

    def flush
      while @queue.size > 0
        next
      end
    end

    private

    def start_thread
      return if @thread and @thread.alive?
      @thread = Thread.new do
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
