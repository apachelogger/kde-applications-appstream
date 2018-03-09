# Copyright (C) 2018 Harald Sitter <sitter@kde.org>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 3 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library.  If not, see <http://www.gnu.org/licenses/>.

require_relative 'test_helper'

class XMLLanguagesTest < Minitest::Test
  def test_from_desktop_entry
    desktop = mock('desktop')
    desktop
      .expects(:localized)
      .with('Comment')
      .returns('en_UK' => 'Colour, old chap!')

    ret = XMLLanguages.from_desktop_entry(desktop, 'Comment')

    assert_equal({ 'en-UK' => 'Colour, old chap!' }, ret)
  end
end
