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

require 'concurrent'
require 'tty/command'
require 'pp'
require 'json'
require 'open-uri'
require 'tmpdir'

require_relative 'app_data'
require_relative 'category'
require_relative 'ci_tooling'
require_relative 'icon_fetcher'
require_relative 'kde_project'
require_relative 'thumbnailer'
require_relative 'xml_languages'

require_relative 'xdg/desktop'
require_relative 'xdg/icon'

class InvalidError < StandardError; end

class AppStreamCollector
  attr_reader :dir
  attr_reader :path
  attr_reader :project

  attr_reader :appdata
  attr_reader :appid

  attr_reader :tmpdir

  def initialize(dir, path:, project:)
    @dir = dir
    @path = path
    @project = project
    @appdata = AppData.new(path).read_as_yaml
    # Sanitize for our purposes (can be either foo.desktop or foo, we always
    # use the latter internally).
    # The value in the appdata must stay as it is or appstream:// urls do not
    # work!
    @appid = appdata['ID'].gsub('.desktop', '')
    # Mutate in the raw data as well. This way subsequent tooling can expecting
    # the id to be standardized.
    appdata['ID'] = @appid
  end

  def xdg_data_dir
    "#{dir}/share/"
  end

  def desktop_file
    @desktop_file ||=
      XDG::ApplicationsLoader.new(appid, extra_data_dirs: ["#{xdg_data_dir}/applications"]).find
  end

  def theme
    @icon_theme ||=
      XDG::IconTheme.new('breeze', extra_data_dirs: ["#{xdg_data_dir}/icons"])
  end

  # FIXME: overridden for git crawling
  def grab_icon
    iconname = desktop_file.icon
    return unless iconname
    IconFetcher.new(iconname, theme).extend_appdata(appdata, cachename: appid)
  end

  def grab_categories
    desktop_categories = desktop_file.categories & MAIN_CATEGORIES
    unless desktop_categories
      # FIXME: record into log
      raise InvalidError, "#{appid} has no main categories. only has #{desktop_categories}"
    end

    appdata['Categories'] ||= []
    # Iff the categories were defined in the appdata as well make sure to
    # filter all !main categories.
    appdata['Categories'] = appdata['Categories'] & MAIN_CATEGORIES
    appdata['Categories'] += desktop_categories
    appdata['Categories'].uniq!
    appdata['Categories'].collect! { |x| Category.to_name(x) }
  end

  def grab_generic_name
    appdata['X-KDE-GenericName'] =
      XMLLanguages.from_desktop_entry(desktop_file, 'GenericName')
  end

  def grab_project
    appdata['X-KDE-Project'] = project.id
    appdata['X-KDE-Repository'] = project.repo
  end

  def grab
    raise InvalidError, "no desktop file for #{appid}" unless desktop_file
    unless desktop_file.show_in?('KDE') && desktop_file.display? && !desktop_file.hidden?
      raise InvalidError, "desktop file for #{appid} not meant for display"
    end

    # FIXME: thumbnailer should not mangle the appdata, it should generate
    #   the thumbnails and we do the mangling...
    Thumbnailer.thumbnail!(appdata)
    grab_icon
    grab_categories
    grab_generic_name
    grab_project

    FileUtils.mkpath('../appdata', verbose: true)
    File.write("../appdata/#{appdata.fetch('ID').gsub('.desktop', '')}.yaml", YAML.dump(appdata))
    File.write("../appdata/#{appdata.fetch('ID').gsub('.desktop', '')}.json", JSON.generate(appdata))

    # FIXME: we should put EVERYTHING into a well defined tree in a tmpdir,
    #   then move it into place in ONE place. so we can easily change where
    #   stuff ends up in the end and know where it is while we are working on
    #   the data
    true
  end

  def self.grab(dir, project:)
    any_good = false
    Dir.glob("#{dir}/**/**.appdata.xml").each do |path|
      warn "  Grabbing #{path}"
      # FIXME: broken blocking all of calligra
      # # https://bugs.kde.org/show_bug.cgi?id=388687
      next if path.include?('org.kde.calligragemini')
      begin
        good = new(dir, path: path, project: project).grab
        any_good ||= good
      rescue InvalidError => e
        warn e
      end
    end
    any_good
  end
end

class GitAppStreamCollector < AppStreamCollector
  def xdg_data_dir
    "#{Dir.pwd}/breeze-icons/share/"
  end

  # FIXME: deferring to appstream via xdg_data_dir
  # def grab_icon
  #   raise 'not implemented'
  #   # a) should look in breeze-icon unpack via theme
  #   # b) should try to find in tree?
  #   # c) maybe an override system?
  # end

  def desktop_file
    files = Dir.glob("#{dir}/**/#{appid}.desktop")
    raise "#{appid}.desktop: #{files.inspect}" unless files.size == 1
    XDG::Desktop.new(files[0])
  end
end
