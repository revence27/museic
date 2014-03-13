#!  /usr/bin/env ruby

require 'pathname'
require 'socket'
require 'thread'

class SequentialSource
  def initialize m3u
    @paths  = Pathname.new(m3u).open 'r' do |fch|
      ans = []
      fch.each_line do |ligne|
        ans << (Pathname.new(m3u).dirname + ligne.strip)
      end
      ans
    end
    @pos    = -1
    @active = nil
  end

  def fetch bytes = 12288
    begin
      if @active.nil? then
        @pos    = (ENV['RANDOM_MUSEIC'] == 'random' ? rand(@paths.length) : @pos + 1)
        @active = @paths[@pos % @paths.length].open('rb')
      end
      got     = @active.read bytes
      if got.length < bytes then
        @active.close
        @active = nil
      end
      got
    end
  rescue Exception => e
    $stderr.puts e.inspect, *e.backtrace
  end
end

class Museic
  def initialize m3us
    @conns  = Queue.new
    @dests  = []
    @srcs   = m3us.map {|m| SequentialSource.new(m)}
    Thread.new do
      self.run
    end
  end
  
  def run
    sz  = 49152
    while true
      conn  = @conns.pop
      @conns << conn
      src   = 0
      while true
        rez = []
        begin
          if @dests.empty? then
            break if @conns.empty?
          end
          @dests  <<  @conns.pop unless @conns.empty?
          cursrc  = @srcs[src % @srcs.length]
          dat = @srcs[src % @srcs.length].fetch(sz)
          @dests.each do |dest|
            dest.write(dat)
            rez << dest
          end
          src = src + 1 if dat.length < sz
        rescue Exception => e
          $stderr.puts e.inspect, *e.backtrace
        end
        @dests  = rez
      end
    end
  end

  def include! conn
    conn.write %[HTTP/1.1 200 OK
Connection: close
Content-Type: application/octet-stream

]
    @conns << conn
  end
end

def run_server srv, mzk
  kyu = Queue.new
  thd = Thread.new(kyu) do |queue|
    queue << thd
    while true
      conn  = srv.accept
      mzk.include! conn
    end
    queue << 0
  end
  kyu
end

def smain args
  if args.length < 2 then
    $stderr.puts %[#{$0} port M3U [M3U ...]]
    return 1
  end
  prt, *etc = args
  TCPServer.open '0.0.0.0', prt.to_i do |srv|
    mzk = Museic.new etc
    sig = run_server srv, mzk
    thd = sig.pop
    ans = sig.pop
    thd.kill
    return ans
  end
  0
end

exit(smain(ARGV))
