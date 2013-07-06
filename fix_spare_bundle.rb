#!/usr/bin/env ruby
#
# Copyright (c) 2013 by Aryk Grosz (mixbook.com & heymosaic.com)
#
# Fix SparseBundle NAS Based Backup Errors
# This script is implementing the intructions from here:
# http://www.garth.org/archives/2011,08,27,169,fix-time-machine-sparsebundle-nas-based-backup-errors.html
#
# The MIT License (MIT)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

sparse_bundle_path = "/Volumes/Time Machine/Macintosh.sparsebundle"
plist_filename_path = "#{sparse_bundle_path}/com.apple.TimeMachine.MachineID.plist"

def run_command(cmd, silence=false)
  puts "Running: #{cmd}" unless silence
  output = `#{cmd}`
  puts "Output:\n---\n#{output}" unless silence
  raise("Unsuccessful Command: #{cmd}") unless $?.success?
  output
end

def sudo(cmd, *args)
  run_command("sudo #{cmd}", *args)
end

def monitor_fsck(first_time=true, &on_fail)
  sleep(5) if first_time # if the command just ran, give it a little time for the file to start getting data
  filename = "/var/log/fsck_hfs.log"
  last_line = sudo("tail -n 1 #{filename}", true)

  success   = last_line =~ /repaired successfully/i
  fail      = last_line =~ /not be repaired/i

  puts "Checking #{filename} until it is either a successful or failure." if first_time
  until success || fail
    sleep(1)
    monitor_fsck(false, &on_fail)
  end
  puts(success ? "Success!" : "Fail!")
  on_fail.call if fail
end

sudo(%{chflags -R nouchg "#{sparse_bundle_path}"})
disk_id = sudo(%{hdiutil attach -nomount -noverify -noautofsck "#{sparse_bundle_path}"})[/dev\/disk(\d)s2/, 1].to_i

monitor_fsck do
  sudo("fsck_hfs -drfy /dev/disk#{disk_id}s2")
  monitor_fsck do
    sudo("fsck_hfs -p /dev/disk#{disk_id}s2")
    monitor_fsck { raise("Tried running #{second_retry}, but it still fails... :(") }
    sudo("fsck_hfs -drfy /dev/disk#{disk_id}s2")
  end
end

return

puts "Modifying #{plist_filename_path}"
plist = File.read(plist_filename_path)
plist.gsub!(Regexp.new("\n\t*<key>RecoveryBackupDeclinedDate</key>\n\t*<date>[\\w\\-:]+</date>"), "")
plist.gsub!(Regexp.new("(<key>VerificationState</key>\n\t*<integer>)\d+(</integer>)"), "\\10\\2")
File.open(plist_filename_path, "w") { |f| f << plist }

puts "Your Done!"