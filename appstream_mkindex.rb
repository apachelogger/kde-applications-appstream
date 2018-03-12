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

require 'json'

Dir.chdir(__dir__) if Dir.pwd != __dir__

appdata_dir = '../appdata'

index ||= {}
Dir.glob("#{appdata_dir}/*.json") do |file|
  next if File.symlink?(file) # Don't include compat symlinks in index.
  data = JSON.parse(File.read(file))
  next unless data['Categories'] # not appdata
  id = data.fetch('X-KDE-ID')
  data.fetch('Categories').uniq.each do |category|
    # NB: category is the Name value. Should l10n for categoresi get implemented
    #   this maybe need rethinking as mapping by name is somewhat fragile.
    index[category] ||= []
    index[category] << id
  end
end

index.values.each(&:sort!)

# Old-ish structure
# Hash of categories and their apps as array inside
File.write("../index.json", JSON.generate(index))
