#!  /usr/bin/env ruby

def dmain args
  args.each do |arg|
    # cmd = %[lame --mp3input -q 0 -b96 --resample 44.1 "${file}.old" "$file"]
    unless arg =~ /\.old$/ then
      narg  = "#{arg}.old"
      $stderr.puts %[Moving #{arg} to .old]
      system %[mv "#{arg}" "#{narg}"]
      arg = narg
    end
    cmd = %[lame --mp3input -q 0 -b96 "#{arg}" "#{arg.gsub(/\.old$/, '')}"]
    $stderr.puts %[Converting #{arg}]
    system cmd
  end
  0
end

exit(dmain(ARGV))
