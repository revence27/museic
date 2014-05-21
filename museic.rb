#!  /usr/bin/env ruby

require 'pathname'
require 'socket'
require 'thread'

BURST_SIZE = 128000
BURST_RATE = 1

class ManagedConnection
  def initialize conn
    @conn   = conn
    @bucket = Queue.new
    @thd    = Thread.new {broadcast!}
  end
  
  def write dat
    @bucket << dat if @bucket.size < 10
  end

  def close
    @thd.kill
  end

  private
  def broadcast!
    begin
      while true
        @conn.write @bucket.pop
      end
    rescue Exception => e
      $stderr.puts e.inspect, *e.backtrace
    end
  end
end

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

  def path
    @paths[@pos]
  end

  def fetch bytes = 12288
    begin
      if @active.nil? then
        @pos    = (ENV['RANDOM_MUSEIC'] == 'not' ? @pos + 1 : rand(@paths.length))
        padding = '  '
        $stderr.print(%[\r #{Pathname.new(self.path).basename.to_s[0 .. -5].gsub('_', ' ').gsub(/^\d+/, '').strip}#{padding * 20}\r])
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
    @mapper = {}
    @srcs   = m3us.map.with_index do |m, mix|
      pn  = Pathname.new m
      nom = pn.basename.to_s.gsub(/\.m3u$/, '')
      @mapper[nom] = mix
      SequentialSource.new(m)
    end
    Thread.new do
      self.run
    end
  end

  def run
    sz  = BURST_SIZE
    cpt = BURST_RATE
    while true
      conn  = @conns.pop
      @conns << conn
      src   = 0
      while true
        rez   = []
        tthen = Time.now
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
        tnow  = Time.now
        # sleep(cpt - (tnow - tthen))
      end
    end
  end

  def include! conn
    conn.write %[HTTP/1.1 200 OK
Connection: close
Content-Type: audio/mpeg

]
    # @conns << ManagedConnection.new(conn)
    @conns << conn
  end
end

class MuseicReq
  attr_reader :uri
  def initialize conn
    @conn = conn
    fill_out!
  end

  def method_missing meth, *args
    @conn.method(meth).call *args
  end

  private
  def fill_out!
    req           = @conn.gets
    mth, @uri, _  = req.strip.split(' ', 3)
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
