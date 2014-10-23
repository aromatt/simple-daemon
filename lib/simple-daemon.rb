require 'simple-daemon/version'
require 'fileutils'

module Simple-Daemon
  class Base

    attr_reader :pid_file, :log_file
    def initialize(opts = {})
      @pid_file = opts[:pid_file] || "/var/run/#{classname}.pid"
      @log_file = opts[:log_file] || "/var/log/#{classname}.log"
    end

    def daemonize
      Controller.daemonize(self)
    end

    def classname
      underscore(self.class.name.split("::").last)
    end

    private

    def underscore(camel_cased_word)
      camel_cased_word.to_s.
      gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
      gsub(/([a-z\d])([A-Z])/, '\1_\2').
      tr("-", "_").
      downcase
    end
  end

  module PidFile
    def self.store(daemon, pid)
      dir = File.dirname(daemon.pid_file)
      if not File.directory?(dir)
        FileUtils.mkdir_p(dir)
      end
      File.open(daemon.pid_file, 'w') { |f| f << pid }
    end

    def self.recall(daemon)
      IO.read(daemon.pid_file).to_i rescue nil
    end
  end

  module Controller
    def self.daemonize(daemon)
      case !ARGV.empty? && ARGV[0]
      when 'start'
        start(daemon)
      when 'stop'
        stop(daemon)
      when 'restart'
        stop(daemon)
        start(daemon)
      else
        puts "Invalid command. Please specify start, stop or restart."
        exit
      end
    end

    def self.start(daemon)
      fork do
        Process.setsid
        exit if fork
        if File.file?(daemon.pid_file)
          puts "Pid file #{daemon.pid_file} already exists.  Not starting."
          exit 1
        end
        PidFile.store(daemon, Process.pid)
        dir = File.dirname daemon.log_file
        FileUtils.mkdir_p dir if not File.directory? dir
        Dir.chdir dir
        File.umask 0000
        log = File.new("#{daemon.log_file}", "a")
        STDIN.reopen "/dev/null"
        STDOUT.reopen log
        STDOUT.sync = true
        STDERR.reopen STDOUT
        STDERR.sync = true
        trap("TERM") { daemon.stop; exit }
        daemon.start
      end
      puts "Daemon started."
    end

    def self.stop(daemon)
      if !File.file?(daemon.pid_file)
        puts "Pid file not found. Is the daemon started?"
        exit
      end

      # Get the pid from the pid file and remove the pid file
      pid = PidFile.recall(daemon)
      FileUtils.rm(daemon.pid_file)

      # Kill all of the processes in the group
      pgid = Process.getpgid(pid)
      if pgid
        Process.kill("-TERM", pgid)
        puts "Daemon stopped."
      else
        puts "Cannot find process group id for pid #{pid}. Killing #{pid} only."
        Process.kill("TERM", pid)
      end
    rescue Errno::ESRCH
      puts "Pid file found, but process was not running. The daemon may have died."
    end
  end
end
