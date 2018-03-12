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

require 'fileutils'
require 'open-uri'
require 'tempfile'
require 'tty/command'

class Thumbnailer
  class Thumbnail
    # Width of the thumbnail.
    attr_reader :width
    # File path of the thumbnail file.
    attr_reader :thumb_file

    attr_reader :url
    attr_reader :thumb_dir_relative
    attr_reader :thumb_file_relative
    attr_reader :last_modified_path

    def initialize(url:, appid:)
      @width = 540
      @url = url
      @thumb_dir = File.join('/thumbnails', appid)
      @thumb_file = File.join(@thumb_dir, File.basename(@url))
      @thumb_dir_relative = File.join('../', @thumb_dir)
      @thumb_file_relative = File.join('../', @thumb_file)
      @last_modified_path = "#{@thumb_file_relative}.last_modified"
      @cmd = TTY::Command.new
    end

    def headers
      return {} unless File.exist?(@last_modified_path)
      { 'If-Modified-Since' => File.read(last_modified_path).strip }
    end

    # Yields [tempfile, openuri::meta]
    def open_as_tempfile(url, headers)
      ext = File.extname(File.basename(url))
      filename = File.basename(File.basename(url), ext)
      open(url, headers) do |img|
        # open for tiny files gives a stringio, read it and force it into
        # a file for conversion. this is really fucked up api behavior...
        Tempfile.open([filename, ext]) do |f|
          f.write(img.read)
          f.close # done writing, close the file to force a sync
          yield f, img
        end
      end
    end

    # assignment branch cond is high because of transietn debug warnings
    def open_orig
      warn url
      open_as_tempfile(url, headers) do |tmpfile, openuri|
        yield tmpfile
        # date is an array, nobody knows why.
        File.write(last_modified_path, openuri.metas.fetch('date').fetch(0))
      end
    rescue OpenURI::HTTPError => e
      code, _msg = e.io.status
      warn [url, code, e]
      raise e unless code == '304' # NotModified
    rescue => e
      raise "#{url} -> #{e}"
    end

    def generate
      open_orig do |f|
        FileUtils.mkpath(thumb_dir_relative, verbose: true)
        # Borrowed from https://www.smashingmagazine.com/2015/06/efficient-image-resizing-with-imagemagick/
        @cmd.run("mogrify -write #{thumb_file_relative} -filter Triangle" \
                 " -define filter:support=2 -thumbnail #{width} -unsharp 0.25x0.25+8+0.065" \
                 ' -dither None -posterize 136 -quality 82 -define jpeg:fancy-upsampling=off' \
                 ' -define png:compression-filter=5 -define png:compression-level=9 ' \
                 ' -define png:compression-strategy=1 -define png:exclude-chunk=all ' \
                 " -interlace none -colorspace sRGB -strip #{f.path}")
      end
    end
  end

  def self.thumbnail!(appdata)
    # FIXME: grab icon out of breeze OR the tree
    return unless appdata['Screenshots'] && !appdata['Screenshots'].empty?
    appdata.fetch('Screenshots').each do |screenshot|
      next if screenshot.fetch('source-image').fetch('lang') != 'C'
      thumb = Thumbnail.new(appid: appdata.fetch('X-KDE-ID'),
                            url: screenshot.fetch('source-image').fetch('url'))
      thumb.generate
      # FIXME: maybe should only set to name of file and resolve in php?
      screenshot['thumbnails'] << { 'url' => thumb.thumb_file,
                                    'width' => thumb.width }
    end
  end
end
