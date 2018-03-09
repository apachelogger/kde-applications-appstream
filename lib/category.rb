# Copyright 2017-2018 Harld Sitter <sitter@kde.org>
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

require_relative 'xdg/desktop'

# This is technically codified in /xdg/menus/kf5-applications.menu but I have
# no parser for that, and breaking it down to it's primary category map is a
# lot more work anyway.
CATEGORY_DESKTOPS_MAP = {
  'AudioVideo' => 'kf5-multimedia.directory',
  'Audio' => 'kf5-multimedia.directory',
  'Video' => 'kf5-multimedia.directory',
  'Development' => 'kf5-development.directory',
  'Education' => 'kf5-education.directory',
  'Game' => 'kf5-games.directory',
  'Graphics' => 'kf5-graphics.directory',
  'Network' => 'kf5-internet.directory',
  'Office' => 'kf5-office.directory',
  'Settings' => 'kf5-settingsmenu.directory',
  'System' => 'kf5-system.directory',
  'Utility' => 'kf5-utilities.directory'
}

MAIN_CATEGORIES = CATEGORY_DESKTOPS_MAP.keys

module Category
  module_function

  def category_desktops
    @category_desktops ||= {}
  end

  def to_name(category)
    desktop = category_desktops.fetch(category)
    desktop.config['Desktop Entry']['Name']
  end
end

# CATEGORY_DESKTOPS = CATEGORY_DESKTOPS_MAP.map do |category, dir|
#   # FIXME: this is currently using system information expecting plasma-workspace to be installed
#   [category, XDG::DesktopDirectoryLoader.new(dir).find]
# end.to_h
#
# MAIN_CATEGORIES = CATEGORY_DESKTOPS.keys
#
# MAIN_CATEGORIES_TO_NAMES = CATEGORY_DESKTOPS.collect do |category, desktop|
#   raise "couldnt find desktop file for #{category}" unless desktop
#   [category, desktop.config['Desktop Entry']['Name']]
# end.to_h
#
# NAMES_TO_MAIN_CATEGORIES = CATEGORY_DESKTOPS.collect do |category, desktop|
#   raise "couldnt find desktop file for #{category}" unless desktop
#   [desktop.config['Desktop Entry']['Name'], category]
# end.to_h
