# frozen_string_literal: true
#
# Copyright (C) 2017 Harald Sitter <sitter@kde.org>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) version 3, or any
# later version accepted by the membership of KDE e.V. (or its
# successor approved by the membership of KDE e.V.), which shall
# act as a proxy defined in Section 6 of version 3 of the license.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library.  If not, see <http://www.gnu.org/licenses/>.

module XDG
  class DesktopFileLoaderBase
    def self.subdir
      'applications'
    end

    def self.file_extension
      '.desktop'
    end

    def self.xdg_data_dirs
      # FIXME: lots of code dupe from icons
      @xdg_data_dirs ||= begin
        dirs = ENV.fetch('XDG_DATA_HOME', '~/.local/share')
        dirs += ':' + ENV.fetch('XDG_DATA_DIRS',
                                '/usr/local/share/:/usr/share/')
        dirs.split(':').collect do |path|
          next if path.include?('..') # relative, skip as per spec
          File.join(File.expand_path(path), subdir)
        end.uniq.compact
      end
    end

    attr_reader :id
    attr_reader :extra_data_dirs

    def initialize(id, extra_data_dirs: [])
      @id = id
      ext = self.class.file_extension
      @id += ext unless @id.end_with?(ext)
      @extra_data_dirs = extra_data_dirs
    end

    def find
      path = find_path
      return path unless path
      Desktop.new(path)
    end

    def find_path
      ids = [id]
      ids += Array.new(id.count('-')) do |i|
        # Run through each hyphen element from the front AND from the back AND
        # both at the same time. Incremently replace them with slashes.
        # We'll drop dupes later.
        # a-b-c-d
        #  i=0 => [a/b-c-d, a-b-c/d, a/b-c/d]
        #  i=1 => [a/b/c-d, a-b/c/d, a/b/c/d]
        #  i=3 => [a/b/c/d, a/b/c/d, a/b/c/d]
        [
          id.split('-', 2 + i).join('/'),
          id.reverse.split('-', 2 + i).join('/').reverse,
          id.split('-', 2 + i).join('/').reverse.split('-', 2 + i).join('/').reverse,
        ]
      end.flatten.uniq.compact
      ids.each do |id|
        file = find_by_id(id)
        return file if file
      end
      nil
    end

    def find_by_id(id)
      warn id
      data_dirs.each do |dir|
        file = File.join(dir, id)
        warn file
        if File.exist?(file)
          warn 'match'
          return file
        end
      end
      nil
    end

    private

    def data_dirs
      extra_data_dirs + self.class.xdg_data_dirs
    end
  end

  class DesktopDirectoryLoader < DesktopFileLoaderBase
    def self.subdir
      'desktop-directories'
    end

    def self.file_extension
      '.directory'
    end
  end

  class ApplicationsLoader < DesktopFileLoaderBase
    def self.subdir
      'applications'
    end

    def self.file_extension
      '.desktop'
    end
  end

  class Desktop
    attr_reader :path
    attr_reader :config

    attr_reader :icon
    attr_reader :categories

    def initialize(path)
      @path = path
      # require 'inifile'
      require 'iniparse'
      # Reasons not to use inifile:
      # - daft default parses assumes ; and # is a comment
      # - even dafter string interpretation stumbling over
      #    GenericName[kk]="Дарға асу" ойны
      #   as it thinks " starts a multi-line quote
      # Reasons not ot use iniparse:
      # - document['Foo'].each iters on IniParse::Lines::* instead of strings.
      @config = IniParse.parse(File.read(path))
      @icon = config['Desktop Entry']['Icon']
      @categories = config['Desktop Entry']['Categories']&.split(';')
    end

    def only_show_in
      @only_show_in = listify(config['Desktop Entry']['OnlyShowIn'])
    end

    def not_show_in
      @not_show_in = listify(config['Desktop Entry']['NotShowIn'])
    end

    def display?
      config['Desktop Entry']['NoDisplay'] != 'true'
    end

    def hidden?
      config['Desktop Entry']['Hidden'] == 'true'
    end

    def show_in?(desktop)
      # Spec makes this easier for us:
      # > The same desktop name may not appear in both OnlyShowIn and NotShowIn of a group.
      # If it is explicitly not shown do that
      return false if not_show_in.include?(desktop)
      # If it only_show_in is set we must be in there
      return only_show_in.include?(desktop) unless only_show_in.empty?
      # Else default to shown.
      true
    end

    # @returns Hash of key/value pairs of all localized values; the master key
    #   gets represented as 'C'
    def localized(key)
      entries = config['Desktop Entry']
      options = entries.find_all { |o| o.key.match(/#{key}($|\[.+\])/) }
      options.collect do |option|
        lang = option.key.match(/#{key}\[(.+)\]/)
        lang = lang ? lang[-1] : 'C' # lang or 'C' for native one
        [lang, option.value]
      end.to_h
    end

    private

    def listify(str)
      return [] unless str
      str.split(';').compact.uniq
    end
  end
end

if $0 == __FILE__
  p XDG::DesktopFileLoader.new('org.kde.filelight').find_path
  p XDG::DesktopFileLoader.new('kde4-kdiff3').find_path
  desktop_file = XDG::DesktopFileLoader.new('org.kde.filelight').find
  p desktop_file.config['Desktop Entry']['Icon']
end
