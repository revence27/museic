#!  /usr/bin/env ruby
# charset: utf-8
# encoding: utf-8

require 'active_record'
require 'net/http'
require 'mp3info'
require 'pathname'
# require 'nokogiri'
require 'socket'
require 'taglib'
require 'thread'
require 'uri'

BURST_SIZE  = 512_000   # Bytes
BURST_RATE  = 3.0       # Seconds

Encoding.default_external = 'UTF-8'

class AlbumArt < ActiveRecord::Base
end
class MuseicSong < ActiveRecord::Base
end
class MuseicSchedule < ActiveRecord::Base
end

class WebResourceParser
  def parse fch
    raise Exception.new(%[Do a better job parsing than does RSS::Parser])
  end
end

class HTResp
  attr_accessor :code, :status

  def initialize con
    _, cod, stt = con.gets.strip.split(/\s+/, 3)
    @code     = cod
    @status   = stt
    @headers  = yield con
  end

  def [] key
    @headers[key.downcase]
  end
end

class ResourceConnection
  def initialize conn
    @http_obj = nil
    @conn     = conn
  end

  def self.get url, hds, follow = 10
    unless url.is_a?(URI) then
      return self.get(URI.parse(url), hds, follow) {|s, g| yield(s, g)}
    end
    sock  = TCPSocket.open(url.hostname, url.port)
    rc    = self.new sock
    rc.get(url, hds) do |got|
      hds['Referer']  = url.to_s
      if got['Location'] then
        self.get(got['Location'], hds, follow - 1) do |s, g|
          yield s, g
        end
      else
        yield sock, got
      end
    end
  end

  def write dat
    @conn.write dat
  end

  def get url, hds
    @conn.puts(%[GET #{url.path}?#{url.query} HTTP/1.1])
    hds['Connection'] = 'close'
    hds['Host']       = url.hostname
    hds['Accept']     = %[audio/mpeg, */*;q=0.9]
    hds['User-Agent'] = %[Muse-ic, by The 27th Comrade]
    hds.keys.each do |cle|
      @conn.puts %[#{cle}: #{hds[cle]}]
    end
    @conn.puts
    yield(read_off_http)
  end

  def http
    @http_obj ||= read_off_http
    @http_obj
  end

  private
  def read_off_http con = nil
    return read_off_http(@conn) if con.nil?
    HTResp.new con do
      ans = {}
      con.each_line do |ligne|
        lg  = ligne.strip
        break if lg.empty?
        k, v = lg.split(':', 2)
        ans[k.downcase] = v.lstrip
      end
      ans
    end
  end
end

class ManagedConnection < ResourceConnection
  def initialize conn
    @conn     = conn
    # @bucket   = Queue.new
    # @pauser   = Queue.new
    # @starter  = Queue.new
    # @thd      = Thread.new {broadcast!}
    super
  end

  def self.multi_write mcs, dat, secs = 5.0
    survs   = mcs
    tplaced = 0
    nadd    = 0
    begt    = Time.now
    pausing = 0.0
    while survs.any? and tplaced < dat.length
      nsurvs  = []
      gaps    = []
      places  = []
      survs.each do |it|
        begin
          begin
            places << it.connection.write_nonblock(dat[tplaced .. -1])
          rescue IO::WaitWritable => wre
            gaps  <<  it
          end
          nsurvs  <<  it
        rescue Errno::EPIPE, Exception => ep
      	  $stderr.puts ep.inspect, *ep.backtrace
        end
      end
      nadd    = places.max || 0
      if nadd.zero? or gaps.length == survs.length then
        conns   = gaps.map &:connection
        tgap    = Time.now - begt
        ans     = IO.select([], conns, conns, [0.0, secs - tgap].max)
        pausing = (ans.nil? ? (pausing / 2.0) + secs : 0.0) # Slow linear back-off
      end
      gat = [pausing, secs - (Time.now - begt)].max
      sleep gat
      tplaced = tplaced + nadd
      survs   = nsurvs
    end
    return survs
  end

  def room?
    @bucket.size < BURST_RATE
  end

  def room
    BURST_SIZE - @bucket.size
  end

  def <=> x
    self.room <=> x.room
  end

  def place dat, them
    if them.length < 2 then
      write(dat)
    else
      if self.room? then
        write(dat)
      else
        @bucket.pop
        write(dat)
      end
    end
  end
  
  def connection
    @conn
  end

  def blocking_write dat
    if @bucket.size < BURST_RATE then
      @bucket << dat
    else
      @starter.clear
      @pauser << @bucket.size
      @starter.pop
      @starter.clear
      write dat
    end
  end

  def close
    @thd.kill
  end

  private
  def broadcast!
    begin
      while true
        if @bucket.size.zero? then
          if @pauser.size.zero? then
            @conn.write @bucket.shift
          else
            @conn.write @bucket.shift until @bucket.size < 1
            @pauser.clear
            @starter << 'Yesu.'
          end
        else
          @conn.write @bucket.shift
        end
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
      fch.each_line do |lg|
        ligne = lg
        dft   = (Pathname.new(m3u).dirname + ligne.strip)
        ans <<  begin
          asur  = URI.parse ligne
          if asur.scheme.nil? then
            dft
          else
            asur
          end
        rescue Exception => e
          dft
        end
        ans << ((asur.scheme.nil? ? dft : asur) rescue dft)
      end
      ans
    end
    @pos    = -1
    @active = nil
  end

  def path
    @paths[@pos]
  end

  def pull_feed_image ur, reds = 10
    resp  = Net::HTTP.get_response(URI.parse(ur))
    return pull_feed_image(resp['Location'], reds - 1) if resp.is_a?(Net::HTTPRedirection) and reds > 0
    sha1ed_image resp.body, resp.content_type
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

  def process_latest_podcast src
    feed    = ResourceConnection.get(src, {}, 10) do |sock, dat|
      WebResourceParser.parse(sock)
    end
    title   = feed.channel.title rescue nil
    copyr   = feed.channel.copyright rescue nil
    slvsha  = pull_feed_image feed.channel.image.url rescue nil
    feed.items.each do |item|
      thepath = item.enclosure.url
      secs    = ([['hour', 60 * 60], ['minute', 60], ['second', 1]].inject(0){|p, n| p + (item.itunes_duration.method(n.first) * n.last)} rescue 0)
      newsong = MuseicSong.new(
        path:         thepath,
        last_play:    Time.now,
        title:        title,
        artist:       (item.itunes_author rescue title),
        album:        title,
        copyright:    copyr,
        year:         item.date.year,
        sleeve_sha1:  slvsha,
        seconds:      secs)
      newsong.save
      return URI.parse(thepath)
    end
  end

  def pull_path_content thepath, reds = 10
    ResourceConnection.get(thepath, {}, reds) do |sock, dat|
      sock
    end
  end

  def curpath
    schs  = MuseicSchedule.where(%[to_run <= NOW() AND to_run > (NOW() - ('1 DAY' :: INTERVAL)) AND last_ran IS NULL])
    if schs.count < 1 then
      @pos  = (ENV['RANDOM_MUSEIC'] == 'not' ? @pos + 1 : rand(@paths.length))
      @paths[@pos % @paths.length]
    else
      itis  = schs.first
      ital  = URI.parse(itis.path)
      # $stderr.puts %[Schedule (#{itis.to_run.localtime}, played at #{Time.now}): #{itis.path}]
      if ital.scheme =~ /^http/ then
        ans           = nil
        begin
          ans = process_latest_podcast ital
        rescue Exception => e
          $stderr.puts e.inspect, *e.backtrace
          itis.last_ran = Time.now
          itis.save
          return curpath
        end
        itis.last_ran = Time.now
        itis.save
        ans
      else
        Pathname.new(schs.first.path)
      end
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
      @active = if thepath.is_a?(Pathname) then
        got = MuseicSong.where('path = ?', thepath.to_s).first
        if got and (thepath.mtime > got.created_at) then
          got.delete
          got = nil
        end
        if not got then
          got = fix thepath.to_s
        end
        got.last_play = Time.now
        got.save
        $stderr.print((%[#{got.title.gsub(/^B\d\d___(\d\d)_(\d)?([^_]+).+$/i, '\2 \3 \1')} [#{got.seconds.divmod(60).map {|x| %[00000#{x}][-2 .. -1]}.join(':')}] #{got.artist} (#{got.album})] + %[#{'  ' * 20}])[0, 78] + "\r")
        thepath.open('rb')
      else
        begin
          pull_path_content(thepath)
        rescue Exception => e
          $stderr.puts e.inspect, *e.backtrace
        end
      end
    end
    got     = @active.read bytes
    if got.to_s.length < bytes then
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
    sz  = (ENV['BURST_SIZE'] or BURST_SIZE).to_i
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
          dat     = @srcs[src % @srcs.length].fetch(sz)
          rez     = ManagedConnection.multi_write(@dests, dat, (ENV['BURST_RATE'] or BURST_RATE).to_f)
          @dests.each do |dest|
            # dest.place(dat, @dests)
            dest.write dat
            # rez << dest
          end
          src = src + 1 if dat.length < sz
        rescue Errno::EPIPE => e
          $stderr.puts e.inspect, *e.backtrace
        end
        @dests  = rez
        tnow  = Time.now
      end
    end
  end

  def include! conn
    conn.write %[HTTP/1.1 200 OK
Connection: close
Content-Type: audio/mpeg

]
    @conns << ManagedConnection.new(conn)
    # @conns << conn
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
