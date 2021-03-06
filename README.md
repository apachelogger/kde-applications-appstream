# Tools

## appstream.rb

Collects **desktop application** appdata from CI install dirs and as a fallback
from Git.

Requires valid screenshots and icons to be available!
Limited functionality with Git fallback. All software should be CI'd really.

Twiddles the following dirs:

- `../appdata/` appdata cache. contains json blobs converted from appdata
- `../icons/` icons cache. contains icons named from their appid (org.kde.foo.svg)
- `../thumbnails` thumbnails cache. scaled to 540 width. subdir per appid

# appstream_mkindex.rb

Iters `../appdata/` and generates an `../appdata/index.json` mapping category
names to appids. The icons for the categories are generated by appstream.rb
and in `../icons/categories/` as downcased version of the name.

# old_apps_compat.rb

Iters `../apps/` and generates compatibility rigging to preserve names from
v1 of the backend, this allows old app urls to remain working.
