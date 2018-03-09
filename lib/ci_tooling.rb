# Copyright 2017 Harald Sitter <sitter@kde.org>
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

require_relative 'fnmatchpattern'

module CITooling
  class RepositoryGroup
    attr_reader :repositories
    attr_reader :platforms

    def initialize(hash)
      p hash
      @repositories = hash['repositories'].collect { |x| FNMatchPattern.new(x) }
      @platforms = hash['platforms']
    end
  end

  class Product
    class RepositoryFilter
      def initialize(branch_groups:, platforms:)
        @branch_groups = branch_groups
        @platforms = platforms
      end

      def filter(product)
        return [] unless @branch_groups.all? { |x| product.branch_groups.include?(x) }
        repos = product.includes.collect do |repo_group|
          next unless @platforms.all? { |x| repo_group.platforms.include?(x) }
          repo_group.repositories
        end
        repos.flatten.compact.uniq
      end
    end

    attr_reader :name
    alias to_s name
    attr_reader :branch_groups
    attr_reader :includes

    def initialize(name, data)
      @name = name || raise
      @branch_groups = data['branchGroups'] || []
      @includes = data['includes'].collect { |x| RepositoryGroup.new(x) }
    end

    def self.list
      data = YAML.load_file('ci-tooling/local-metadata/product-definitions.yaml')
      data.collect do |name, hash|
        new(name, hash)
      end
    end
  end
end
