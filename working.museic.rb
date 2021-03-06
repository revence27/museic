#!  /usr/bin/env ruby
# charset: utf-8
# encoding: utf-8

require 'pathname'
require 'socket'
require 'thread'
require 'active_record'
require 'mp3info'
require 'taglib'

BURST_SIZE = 128000
BURST_RATE = 1

Encoding.default_external = 'UTF-8'

class AlbumArt < ActiveRecord::Base
end
class MuseicSong < ActiveRecord::Base
end
class MuseicSchedule < ActiveRecord::Base
end

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
    # @db     = PGconn.connect(dbname: 'museic', user: 'museic')
    @db     = ActiveRecord::Base.establish_connection(adapter: 'postgresql', database: 'museic', user: 'museic')
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

  def pull_raw_pic bin
    return [nil, nil] unless bin
    magick  = bin[0, 6]
    if magick == "\x00JPG\x00\x00" then
      ['image/jpeg', bin[6 .. -1]]
    elsif magick == "\x00PNG\x00\x00" then
      ['image/png', bin[6 .. -1]]
    else
      ['application/octet-stream', bin[6 .. -1]]
    end
  end

  def sha1ed_image pic, pic_ct
    if pic then
      ss    = (Digest::SHA1.new << pic).to_s
      falb  = AlbumArt.where('sha1_sig = ?', [ss]).first
      AlbumArt.new(sha1_sig: ss, content_type: pic_ct, rawdata: pic).save unless falb
      ss
    else
      nil
    end
  end

  def fix thepath
    tag     = {title: thepath.split('/').last.split('.')[0 .. -2].join('.').force_encoding('UTF-8'), artist: 'Unidentified Artist', album: 'Unidentified Album', year: 0}
    pic_ct  = nil
    pic     = nil
    secs    = 0
    begin
      Mp3Info.open thepath do |mi|
        tag = {title: mi.tag.title || tag[:title], artist: mi.tag.artist || tag[:artist], album: mi.tag.album || tag[:album], year: mi.tag.year || tag[:year], copyright: (mi.tag.copyright rescue nil)}
        thepics, thecop =
          [begin
            mi.tag2.pictures
          rescue Exception => e
            apix  = mi.tag2.APIC
            if apix.length > 1 then
              fst       = apix.sort.first
              if fst =~ /image\/jpeg/ then
                [['1_.jpg', fst[14 .. -1]]]
              elsif fst =~ /image\/jpg/ then
                [['1_.jpg', fst[13 .. -1]]]
              else
                [['1_.png', fst[13 .. -1]]]
              end
            else
              $stderr.puts "\nWhat image tags are in #{thepath}?"
              []
            end
          end,
          begin
              mi.tag2.TCOP || mi.tag2.WCOP || nil
          rescue Exception => e
              $stderr.puts "\nWhat image tags are in #{thepath}?"
              nil
          end]
        tag[:copyright] ||= thecop
        unless thepics.length.zero? then
          thepics.each do |desc, dat|
            pic_ct  ||= {'jpg' => 'image/jpeg', 'png' => 'image/png'}[desc.force_encoding('UTF-8').split('.').last.downcase]
            if pic_ct then
              pic ||= dat.force_encoding('UTF-8')
            end
          end
        else
          itsies  = pull_raw_pic mi.tag2.PIC
          pic_ct  ||= itsies[0]
          pic     ||= itsies[1]
        end
      end
    rescue Exception => e
      $stderr.puts e.inspect, *e.backtrace
    end
    begin
      TagLib::FileRef.open thepath do |tf|
        unless tf.null? then
          secs  = (tf.audio_properties.length rescue secs).to_i
        end
      end
    rescue Exception => e
      # Ignore for now.
    end
    slvsha  = sha1ed_image pic, pic_ct
    newsong = MuseicSong.new(
      path:         thepath.force_encoding('UTF-8'),
      last_play:    Time.now,
      title:        tag[:title].force_encoding('UTF-8'),
      artist:       tag[:artist].force_encoding('UTF-8'),
      album:        tag[:album].force_encoding('UTF-8'),
      copyright:    tag[:copyright],
      year:         tag[:year].to_i,
      sleeve_sha1:  slvsha,
      # sleeve:     pic,
      # sleeve_ct:  pic_ct,
      seconds:      secs)
    newsong.save
    newsong
  end

  
  def curpath
    schs  = MuseicSchedule.where(%[to_run <= NOW() AND to_run > (NOW() - ('1 DAY' :: INTERVAL)) AND last_ran IS NULL])
    if schs.count < 1 then
      @pos  = (ENV['RANDOM_MUSEIC'] == 'not' ? @pos + 1 : rand(@paths.length))
      @paths[@pos % @paths.length]
    else
      Pathname.new(schs.first.path)
    end
  end

  def active_fetch bytes
    if @active.nil? then
      thepath = if block_given? then
                  ans = yield
                  if ans.nil? then
                    curpath
                  else
                    ans
                  end
                else
                  curpath
                end
      got     = MuseicSong.where('path = ?', thepath.to_s).first
      if got and (thepath.mtime > got.created_at) then
        got.delete
        got = nil
      end
      if not got then
        got = fix thepath.to_s
      end
      got.last_play = Time.now
      got.save
      @active = thepath.open('rb')
      $stderr.print((%[#{got.title.gsub(/^B\d\d___(\d\d)_(\d)?([^_]+).+$/i, '\2 \3 \1')} [#{got.seconds.divmod(60).map {|x| %[00000#{x}][-2 .. -1]}.join(':')}] #{got.artist} (#{got.album})] + %[#{'  ' * 20}])[0, 78] + "\r")
      $stderr.flush
    end
    got     = @active.read bytes
    if got.length < bytes then
      @active.close
      @active = nil
    end
    [@active, got]
  end

  def fetch bytes = 12288
    @active, got  = active_fetch bytes
    got
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
        rescue Errno::EPIPE => e
          # $stderr.puts e.inspect, *e.backtrace
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
