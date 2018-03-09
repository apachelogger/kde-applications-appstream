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
  class IconTheme
    class Directory
      attr_reader :path
      alias to_s path
      attr_reader :size
      attr_reader :scale
      attr_reader :context
      attr_reader :type
      attr_reader :max_size
      attr_reader :min_size
      attr_reader :threshold

      def initialize(path, hash)
        @path = path
        @size = hash['Size']
        @scale = hash['Scale'] || 1
        @context = hash['Context']
        @type = hash['Type'] || 'Threshold'
        @max_size = hash['MaxSize'] || @size
        @min_size = hash['MinSize'] || @size
        @threshold = hash['Threshold'] || 2
      end

      def matches_size?(iconsize, iconscale)
        return false if iconscale != scale
        # FIXME type should be a const maybe definitely and a symbol at athat
        case type
        when 'Fixed' then size == iconsize
        when 'Scalable' then min_size <= iconsize && iconsize <= max_size
        when 'Threshold'
          size - threshold <= iconsize &&
            iconsize <= size + threshold
        else
          raise "unknown type #{type}"
        end
      end

      def size_distance(iconsize, iconscale)
        # FIXME type should be a const maybe definitely and a symbol at athat
        scaled_icon_size = iconsize * iconscale
        scaled_subdir_size = size * scale
        scaled_subdir_min = min_size * scale
        scaled_subdir_max = max_size * scale
        case type
        when 'Fixed' then (scaled_subdir_size - scaled_icon_size).abs
        when 'Scalable'
          if scaled_icon_size < scaled_subdir_min
            scaled_subdir_min - scaled_icon_size
          elsif scaled_icon_size > scaled_subdir_max
            scaled_icon_size - scaled_subdir_max
          else
            0
          end
        when 'Threshold'
          if scaled_icon_size < (size - threshold) * scale
            scaled_subdir_min - scaled_icon_size
          elsif scaled_icon_size > (size + threshold) * scale
            scaled_icon_size - scaled_subdir_max
          else
            0
          end
        else
          raise "unknown type #{type}"
        end
      end
    end

    def self.xdg_data_dirs
      @xdg_data_dirs ||= begin
        dirs = ENV.fetch('XDG_DATA_HOME', '~/.local/share')
        dirs += ':' + ENV.fetch('XDG_DATA_DIRS',
                                '/usr/local/share/:/usr/share/')
        dirs.split(':').collect do |path|
          next if path.include?('..') # relative, skip as per spec
          File.join(File.expand_path(path), 'icons')
        end.uniq.compact
      end
    end

    def self.icon_dirs
      @icon_dirs ||=
        ["#{Dir.home}/.icons"] + xdg_data_dirs + ['/usr/share/pixmaps']
    end

    # These are the toplevel theme dir locations /usr/share/icons/foo etc.
    attr_reader :dirs
    # The dirs which were defined as extra on top of the defaults
    # This is a subset of dirs!
    attr_reader :extra_data_dirs
    # Config object
    attr_reader :config

    attr_reader :parents
    attr_reader :directories
    alias subdirs directories

    def initialize(name, extra_data_dirs: [])
      data_dirs = extra_data_dirs + self.class.icon_dirs
      @dirs = data_dirs.collect { |x| File.join(x, name) }
      @extra_data_dirs = extra_data_dirs
      @config = load_config
      return unless @config
      theme_config = @config['Icon Theme']
      @parents = []
      if theme_config['Inherits']
        @parents = theme_config['Inherits'].split(',').collect { |x| self.class.new(x, extra_data_dirs: extra_data_dirs) }
      end
      @directories = theme_config['Directories']
      @directories += theme_config['ScaledDirectories'] if theme_config['ScaledDirectories']
      @directories = @directories.split(',').collect! do |x|
        Directory.new(x, @config[x])
      end
    end

    def valid?
      dirs.any? { |x| File.exist?(File.join(x, 'index.theme')) }
    end

    private

    def load_config
      dir = dirs.find { |x| File.exist?(File.join(x, 'index.theme')) }
      # FIXME: what if the theme doesn't exist though?
      return nil unless dir
      config_file = File.join(dir, 'index.theme')
      require 'inifile'
      IniFile.load(config_file, comment: '#')
    end
  end

  class IconLoader
    EXTENSIONS = %w[png svg svgz xpm].freeze
    attr_reader :icon
    attr_reader :size
    attr_reader :scale
    attr_reader :theme

    def initialize(icon, size, theme, scale: 1)
      @icon = icon
      @size = size
      @theme = theme
      @scale = scale
    end

    def hicolor_theme
      IconTheme.new('hicolor', extra_data_dirs: theme.extra_data_dirs)
    end

    def find_icon
      filename = find_icon_in_theme(theme)
      return filename if filename

      # problemo. theme is shitty titty
      filename = find_icon_in_theme(hicolor_theme)
      return filename if filename

      lookup_fallback_icon
    end

    def find_icon_in_theme(theme)
      filename = lookup_icon(theme)
      return filename if filename

      theme.parents.each do |parent|
        filename = find_icon_in_theme(parent)
        return filename if filename
      end

      nil
    end

    def lookup_icon(theme)
      theme.dirs.each do |dir|
        theme.subdirs.each do |subdir|
          next unless subdir.matches_size?(size, scale)
          EXTENSIONS.each do |ext|
            file = "#{dir}/#{subdir}/#{icon}.#{ext}"
            return file if File.exist?(file)
          end
        end
      end

      closest_file = nil
      minimal_size = 999_999_999 # Ints in ruby are technically limitless.
      theme.dirs.each do |dir|
        theme.subdirs.each do |subdir|
          EXTENSIONS.each do |ext|
            file = "#{dir}/#{subdir}/#{icon}.#{ext}"
            next unless File.exist?(file)
            distance = subdir.size_distance(size, scale)
            if distance < minimal_size
              closest_file = file
              minimal_size = distance
            end
          end
        end
      end

      closest_file
    end

    def lookup_fallback_icon
      theme.dirs.each do |dir|
        EXTENSIONS.each do |ext|
          file = "#{dir}/#{icon}.#{ext}"
          return file if File.exist?(file)
        end
      end

      nil
    end
  end

  class Icon
    def self.find_path(icon, size, theme, scale: 1)
      IconLoader.new(icon, size, theme, scale: scale).find_icon
    end
  end
end

if $0 == __FILE__
  theme = XDG::IconTheme.new(ARGV[0])
  puts "valid? #{theme.valid?}"
  p XDG::Icon.find_path('filelight', 32, theme)
  p XDG::Icon.find_path('foobar', 32, theme)
end
