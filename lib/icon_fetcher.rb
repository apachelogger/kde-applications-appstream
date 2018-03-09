# Copyright 2017 Harld Sitter <sitter@kde.org>
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

require_relative 'xdg/icon'

class IconFetcher
  attr_reader :iconname
  attr_reader :theme

  def initialize(iconname, theme)
    @iconname = iconname
    @theme = theme
  end

  def extend_appdata(appdata, cachename:, subdir: '')
    icon = XDG::Icon.find_path(iconname, 48, theme)
    raise InvalidError, "Couldn't find icon #{iconname}" unless icon
    cachefile = cachename + File.extname(icon)
    FileUtils.mkpath("../icons/#{subdir}")
    FileUtils.cp(icon, "../icons/#{subdir}/#{cachefile}", verbose: true)

    appdata['Icon'] ||= {}
    icon = appdata['Icon']
    icon['local'] ||= []
    icon['local'] << { 'name' => cachefile }
  end
end
