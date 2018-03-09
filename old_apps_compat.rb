#!/usr/bin/env ruby
#
# Copyright 2018 Harld Sitter <sitter@kde.org>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License or (at your option) version 3 or any later version
# accepted by the membership of KDE e.V. (or its successor approved
# by the membership of KDE e.V.), which shall act as a proxy
# defined in Section 14 of version 3 of the license.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'fileutils'
require 'json'
require 'pp'

apps_dir = '../apps'
appdata_dir = '../appdata'
appdata_extensions_dir = '../appdata-extensions'

# Hints for name conversion if $oldname != org.kde.$oldname
HINTS = {
  'kdepartitionmanager' => 'partitionmanager',
  'kmail' => 'kmail2',
  'plan' => 'calligraplan',
  'sheets' => 'calligrasheets',
  'stage' => 'calligrastage',
  'words' => 'calligrawords',
}

apps = Dir.glob("#{apps_dir}/*.json")
apps = apps.select { |x| x.include?('_generated.json') }
apps = apps.collect { |x| File.basename(x, '_generated.json') }

# map to new ids
map = {}
apps.each do |app|
  appid = app.dup
  appid = HINTS[appid] if HINTS.include?(appid)
  next unless File.exist?("#{appdata_dir}/org.kde.#{appid}.json")
  map[app] = "org.kde.#{appid}"
end

pp map

# Check if old id has extra data we need to map into the new format as
# extensions because appdata doesn't support them natively.
compat_blobs = {}
map.each do |oldid, newid|
  data_map = {
    'forum' => 'X-KDE-Forum',
    'irc' => 'X-KDE-IRC',
    'mailing lists' => 'X-KDE-MailingLists'
  }
  old_data = JSON.parse(File.read("#{apps_dir}/#{oldid}.json"))
  compat_data = {}
  data_map.each do |oldkey, newkey|
    compat_data[newkey] = old_data[oldkey] if old_data[oldkey]
  end
  next if compat_data.empty?
  compat_blobs[newid] = compat_data
end

map.each do |oldid, newid|
  old_name = "#{oldid}.json"
  compat_path = File.join(appdata_dir, old_name)
  new_name = "#{newid}.json"
  extension_path = File.join(appdata_extensions_dir, new_name)

  # Symlink old name to new so URLs stay valid.
  if File.exist?(compat_path) && !File.symlink?(compat_path)
    raise "unexpected !symlink #{compat_path}"
  end
  FileUtils.ln_sf(new_name, compat_path, verbose: true)

  # Dump data blob into extension location.
  # This should not be used and is only here to not lose data, extension data
  # should be put into the actual appdata files of the projects.
  # TODO: check if the yaml converter actually knows what to do with unknown
  #   data blobs, I have a feeling it will simply not translate them - sitter
  compat_data = compat_blobs[newid]
  File.write(extension_path, JSON.pretty_generate(compat_data)) if compat_data
end

diff = apps - map.keys
raise "missing maps for #{diff.inspect}" unless diff.empty?
