#!  /usr/bin/env ruby
# charset: utf-8
# encoding: utf-8

require 'active_record'

Encoding.default_external = 'UTF-8'

class AlbumArt < ActiveRecord::Base
end
class MuseicSong < ActiveRecord::Base
end
class MuseicSchedule < ActiveRecord::Base
end

def record_schedule path, time, date
  ms    = MuseicSchedule.new(path: path, to_run: Time.mktime(date.year, date.month, date.day, time.first || 0, time.last || 0))
  ms.save
  ms
end

def smain args
  if args.length < 1 then
    $stderr.puts %[#{$0} path [time] [date]\n\tdate: dd/mm/yyyy\n\ttime: HH:MM\n\n\tValues default to now (#{Time.now}).]
    return 1
  end
  path  = args.shift
  time  = proc do |dat|
            dat.split(/\D+/)[0, 2].map {|x| x.gsub(/^0+/, '').to_i}
          end.call(args.shift || Time.now.strftime('%H:%M'))
  date  = Time.now
  if args.any? then
    date  = Time.mktime(* args.shift.split(/\D+/))
  end
  ActiveRecord::Base.establish_connection(adapter: 'postgresql', database: 'museic', user: 'museic')
  record_schedule path, time, date
  0
end

exit(smain(ARGV))
