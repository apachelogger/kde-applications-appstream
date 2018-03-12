#!/usr/bin/env ruby
#
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

require_relative 'lib/category'
require_relative 'lib/collectors'

Dir.chdir(__dir__) if Dir.pwd != __dir__

def system(*args)
  TTY::Command.new(uuid: false).run(*args)
end

def prepare!
  unless File.exist?('ci-tooling')
    system('git', 'clone', '--depth', '1', 'https://anongit.kde.org/sysadmin/ci-tooling')
  end
  unless File.exist?('ci-tooling/kde-build-metadata')
    system('git', 'clone', '--depth', '1', 'https://anongit.kde.org/kde-build-metadata', chdir: 'ci-tooling/')
  end
  unless File.exist?('ci-tooling/repo-metadata')
    system('git', 'clone', '--depth', '1', 'https://anongit.kde.org/sysadmin/repo-metadata', chdir: 'ci-tooling/')
  end

  # apt install imagemagick appstream hicolor-icon-theme
end

prepare!

branch_group = 'kf5-qt5'

platform_blacklist = [
  FNMatchPattern.new('Windows*'),
  FNMatchPattern.new('Android*'),
  FNMatchPattern.new('*BSD*'),
]

products = CITooling::Product.list

projects = KDE::Project.list
projects.select! do |project|
  # Playground aren't ready for the public.
  next if project.start_with?('playground/')
  # Neither are apps in review.
  next if project.start_with?('kdereview/')
  # Neither is historical stuff
  next if project.start_with?('historical/')
  # Nor unmaintained stuff
  next if project.start_with?('unmaintained/')
  # Frameworks aren't apps.
  next if project.start_with?('frameworks/')
  # Neither are books
  next if project.start_with?('books/')
  # Nor websites
  next if project.start_with?('websites/')
  # or sysadmin stuff
  next if project.start_with?('sysadmin/')
  # or kdesupport (the frameworks of the 90's)
  next if project.start_with?('kdesupport/')
  # or others which is non-code things
  next if project.start_with?('others/')

  # Explicitly whitelist stuff we later need to have data for git crawl.
  # next true if File.basename(project) == 'breeze-icons'
  # next true if File.basename(project) == 'plasma-workspace'

  # TODO: broken crawl in some capacity:
  # kexi (no CI and failed to find desktop file in git)
  # kaudiocreator (no CI and no icon in breeze)
  # kcachegrind (no CI and no icon in breeze)
  # knights (no CI and no icon in breeze)
  # konqueror (failed to find org.kde.konqueror.desktop in install tree)
  # kwave (no CI and desktop file build-time dependent)
  # smb4k (no CI and no icon in breeze)
  # symboleditor (broken screenshots)
  # umbrello (broken id mapping)
  # kxstitch (no CI and no icon in breeze)
  # kio-gdrive can't find desktop file maybe wrong type desktop)

  # TODO: no appdata on:
  # kopete
  # jovie
  # kbounce
  # kbreakout
  # kcharselect
  # kcolorchooser
  # kdiamond
  # kfourinline
  # kgeography
  # killbots
  # kinfocenter
  # kmplayer
  # knemo
  # knetwalk
  # krecipes
  # kscd
  # ksnapshot
  # kst
  # ksystemlog
  # kwalletmanager
  # rsibreak

  # TODO: unmaintained but on old apps list:
  # blogilo

  # TODO: missing?
  # kappfinder (seems to have disappeared entirely)
  # kdiskfree (seems to not exist)
  # keurocalc (seem to not exist)
  # kfilereplace
  # kftpgrabber
  # kioskadmintool
  # klinkstatus
  # kmid
  # kmldonkey
  # knode
  # kommander
  # kpager
  # kpatience
  # kppp
  # kremotecontrol
  # ksame
  # ksig
  # kuiviewer
  # kwlan

  # TODO: playground but was on apps list:
  # kdiff3

  if ARGV[0]
    next true if project.end_with?(ARGV[0])
    next false
  end

  # TODO: compile list of apps with hicolor only icons and tell andreask

  next if %w[simon signon-kwallet-extension kdev-control-flow].any? { |x| project.end_with?(x) }
  # https://bugs.kde.org/show_bug.cgi?id=391528
  next if project.end_with?('heaptrack')
  # https://bugs.kde.org/show_bug.cgi?id=391554
  next if project.end_with?('apper')
  # https://bugs.kde.org/show_bug.cgi?id=391555
  next if project.end_with?('kimtoy')
  # https://phabricator.kde.org/D11187
  next if project.end_with?('kio-stash')
  # No CI and in-git desktop file is .desktop.in. Can't crawl this
  next if project.end_with?('kwave')
  # https://bugs.kde.org/show_bug.cgi?id=391559
  next if project.end_with?('umbrello')
  # No CI and in-git desktop file is .desktop.cmake. Can't crawl This
  next if project.end_with?('ark')
  # https://phabricator.kde.org/D11186
  next if project.end_with?('kio-gdrive')
  true
end
projects = Concurrent::Array.new(projects) # make thread-safe

# TODO list of not processed items:
# kactivitymanagerd no appdata
# kde-gtk-config no appdata
# khotkeys no appdata
# kmenuedit no appdata
# ksysguard no appdata
# sddm-kcm no appdata
# user-manager no appdata

# Retrieves data into tmpdir/subdirOfProject
network_pool = Concurrent::FixedThreadPool.new(8)
# Processes extracted data. Manipulates process env, can only have one running.
processing_pool = Concurrent::FixedThreadPool.new(4)

# Artifacts are tarred into products, since this is grouping stuffed on top of
# project metadata we'll simply try and ignore failure. Otherwise this gets
# overengineered quickly.
# FIXME: needs to raise some sort of error on products which have no appdata!

dep_file = "ci-tooling/kde-build-metadata/dependency-data-#{branch_group}"
File.write(dep_file, '') # truncate

Dir.mktmpdir do |tmpdir|
  break if File.exist?('breeze-icons') && File.exist?('plasma-workspace')
  products.each do |product| # FIXME: excessive copy pasta from install iter
    # Aggreagte all platforms so we can iter on them.
    platforms = product.includes.collect { |x| x.platforms }
    platforms = platforms.flatten.compact.uniq
    # First filter all unsupported ones though.
    platforms.reject! { |x| platform_blacklist.any? { |y| y == x } }
    platforms.each do |platform|
      filter = CITooling::Product::RepositoryFilter.new(branch_groups: [branch_group], platforms: [platform])
      projects_in_product = filter.filter(product)
      projects.each do |project|
        basename = File.basename(project)

        break if File.exist?(basename)
        next unless projects_in_product.include?(project)
        next unless %w[breeze-icons plasma-workspace].any? { |x| basename == x }

        dep_project = "#{project}-appstream"
        dir = File.join(tmpdir, project)
        File.write(dep_file, "#{File.read(dep_file)}\n#{dep_project}: #{project}")
        FileUtils.mkpath(dir, verbose: true) unless File.exist?(dir)

        res = TTY::Command.new.run!(
               'python3', '-u', 'ci-tooling/helpers/prepare-dependencies.py',
               '--product', product,
               '--project', dep_project,
               '--branchGroup', branch_group,
               '--environment', 'production',
               '--platform', platform,
               '--installTo', dir)
        next unless res.success?
        FileUtils.rm_rf(basename, verbose: true)
        FileUtils.cp_r(dir, basename, verbose: true)
      end
    end
  end
end

raise unless File.exist?('breeze-icons') && File.exist?('plasma-workspace')

CATEGORY_DESKTOPS_MAP.each do |category, desktop_id|
  loader = XDG::DesktopDirectoryLoader.new(
    desktop_id, extra_data_dirs: [File.join(Dir.pwd, 'plasma-workspace/share/desktop-directories')]
  )
  desktop = loader.find
  p desktop
  raise unless desktop
  entries = desktop.config['Desktop Entry']
  Category.category_desktops[category] = desktop
  name = entries['Name']
  theme = XDG::IconTheme.new('breeze', extra_data_dirs: ["#{Dir.pwd}/breeze-icons/share/"])
  IconFetcher.new(entries['Icon'], theme).extend_appdata({}, cachename: name.downcase, subdir: 'categories')
end

Dir.mktmpdir do |tmpdir|
  products.each do |product|
    # Aggreagte all platforms so we can iter on them.
    platforms = product.includes.collect { |x| x.platforms }
    platforms = platforms.flatten.compact.uniq
    # First filter all unsupported ones though.
    platforms.reject! { |x| platform_blacklist.any? { |y| y == x } }
    platforms.each do |platform|
      promises = []
      filter = CITooling::Product::RepositoryFilter.new(branch_groups: [branch_group], platforms: [platform])
      projects_in_product = filter.filter(product)
      projects.each do |project|
        unless projects_in_product.include?(project)
          # puts "skipping #{project}"
          next
        end
        # puts "picking #{project}"
        # NB: the basename of the project must be different or the dep resolver
        #   will think it is a looping dep (even when it is in a different scope
        #   e.g. appstream/)
        dep_project = "#{project}-appstream"
        dir = File.join(tmpdir, project)

        File.write(dep_file, "#{File.read(dep_file)}\n#{dep_project}: #{project}")
        warn "mangling #{dir}"
        FileUtils.mkpath(dir, verbose: true) unless File.exist?(dir)

        promises << Concurrent::Promise.new(executor: network_pool) do
          system(
                 'python3', '-u', 'ci-tooling/helpers/prepare-dependencies.py',
                 '--product', product,
                 '--project', dep_project,
                 '--branchGroup', branch_group,
                 '--environment', 'production',
                 '--platform', platform,
                 '--installTo', dir) || raise
           warn 'END'
        end.then(Proc.new { FileUtils.rm_rf(dir, verbose: true) }, processing_pool) do
          warn "processing #{dir}"
          # FIXME: !!! by only removing the project if it grabbed we run the prepare
          #   multiple times if multiple platforms are available even though
          #   we have found an install, we just didn't find any data.
          #   this needs a second list kept of projects we looked at it already.
          #   the projects array is the list of projects we found something for
          #   so git has a shrunk list. we still want git to run on projects
          #   that had a tree but no data though.
          if AppStreamCollector.grab(dir, project: KDE::Project.get(project))
            projects.delete(project)
          end
          FileUtils.rm_rf(dir)
        end
      end

      # Start the promises after iteration. Otherwise we might delete entries
      # from projects while still eaching it, which can screw up the iter
      # position and make us skip stuff randomly.
      promises.each(&:execute)

      promises.each do |x|
        x.wait
        # FIXME: sysetm shits itself on shitty jobs
        raise x.reason if x.rejected?
      end
    end
  end
end

p projects
warn 'procprocproc'

# Crawl what remains of projects through git
Dir.mktmpdir do |tmpdir|
  projects.reject! do |project_id|
    project = KDE::Project.get(project_id)
    dir = File.join(tmpdir, project.id)
    TTY::Command.new.run("git clone --depth 1 https://anongit.kde.org/#{project.repo} #{dir}")
    next true if GitAppStreamCollector.grab(dir, project: project)
    FileUtils.rm_rf(dir)
    false
  end
end

warn "not processed: #{projects}"

# FIXME: run list builder
# FIXME: run ids symlink to keep backwards compat

__END__

not processed: ["extragear/base/atcore", "extragear/base/kwebkitpart", "extragear/base/latte-dock", "extragear/base/mangonel", "extragear/base/nepomuk-webminer", "extragear/base/networkmanagement", "extragear/base/plasma-angelfish", "extragear/base/plasma-camera", "extragear/base/plasma-mobile", "extragear/base/plasma-mobile/plasma-mobile-config", "extragear/base/plasma-samegame", "extragear/base/plasma-settings", "extragear/base/polkit-kde-kcmodules-1", "extragear/base/qtcurve", "extragear/base/share-like-connect", "extragear/base/wacomtablet", "extragear/edu/gcompris-data", "extragear/games/knights", "extragear/graphics/digikam/digikam-doc", "extragear/graphics/digikam/digikam-software-compilation", "extragear/graphics/kdiagram", "extragear/graphics/kipi-plugins", "extragear/graphics/kipi-plugins/kipi-plugins-doc", "extragear/graphics/kolor-manager", "extragear/graphics/krita-extensions/krita-analogies", "extragear/graphics/krita-extensions/krita-cimg", "extragear/graphics/krita-extensions/krita-ctlbrush", "extragear/graphics/krita-extensions/krita-deskew", "extragear/graphics/krita-extensions/krita-dither", "extragear/graphics/krita-extensions/krita-grayscalizer", "extragear/graphics/krita-extensions/krita-humanbody", "extragear/graphics/krita-extensions/krita-imagecomplete", "extragear/graphics/krita-extensions/krita-linesampler", "extragear/graphics/krita-extensions/krita-pyramidalsharpening", "extragear/graphics/ksnapshot", "extragear/graphics/kst-plot", "extragear/graphics/kxstitch", "extragear/graphics/symboleditor", "extragear/kdevelop/plugins/kdev-php", "extragear/kdevelop/plugins/kdev-python", "extragear/kdevelop/utilities/kdevelop-pg-qt", "extragear/libs/kdb", "extragear/libs/kproperty", "extragear/libs/kreport", "extragear/libs/kuserfeedback", "extragear/libs/libkfbapi", "extragear/libs/libkvkontakte", "extragear/libs/libmediawiki", "extragear/multimedia/amarok/amarok-history", "extragear/multimedia/elisa", "extragear/multimedia/kaudiocreator", "extragear/multimedia/kmplayer", "extragear/multimedia/plasma-mediacenter", "extragear/network/bodega-server", "extragear/network/bodega-webapp-client", "extragear/network/kdeconnect-android", "extragear/network/kdeconnect-kde", "extragear/network/kio-gopher", "extragear/network/knemo", "extragear/network/libktorrent", "extragear/network/rekonq", "extragear/network/smb4k", "extragear/network/telepathy/telepathy-logger-qt", "extragear/network/wicd-kde", "extragear/office/alkimia", "extragear/office/kbibtex-testset", "extragear/pim/trojita", "extragear/sdk/clazy", "extragear/sdk/kdesvn", "extragear/sdk/massif-visualizer", "extragear/sysadmin/kcm-grub2", "extragear/sysadmin/kpmcore", "extragear/sysadmin/libdebconf-kde", "extragear/sysadmin/libqapt", "extragear/sysadmin/partitionmanager", "extragear/utils/kdesrc-build", "extragear/utils/kmarkdownwebview", "extragear/utils/krecipes", "extragear/utils/plasma-mycroft", "extragear/utils/rsibreak", "kde/applications/baloo-widgets", "kde/applications/kdialog", "kde/applications/keditbookmarks", "kde/applications/konqueror", "kde/kde-workspace", "kde/kdeadmin/kcron", "kde/kdeadmin/ksystemlog", "kde/kdebindings/csharp/kimono", "kde/kdebindings/csharp/qyoto", "kde/kdebindings/kross-interpreters", "kde/kdebindings/perl/perlkde", "kde/kdebindings/perl/perlqt", "kde/kdebindings/python/pykde4", "kde/kdebindings/python/pykde5", "kde/kdebindings/ruby/korundum", "kde/kdebindings/ruby/qtruby", "kde/kdebindings/smoke/smokegen", "kde/kdebindings/smoke/smokekde", "kde/kdebindings/smoke/smokeqt", "kde/kdeedu/analitza", "kde/kdeedu/kdeedu-data", "kde/kdeedu/kgeography", "kde/kdeedu/kqtquickcharts", "kde/kdeedu/libkeduvocdocument", "kde/kdeexamples", "kde/kdegames/kbounce", "kde/kdegames/kbreakout", "kde/kdegames/kdiamond", "kde/kdegames/kfourinline", "kde/kdegames/killbots", "kde/kdegames/klickety", "kde/kdegames/knetwalk", "kde/kdegames/kpat", "kde/kdegames/libkdegames", "kde/kdegames/libkmahjongg", "kde/kdegraphics", "kde/kdegraphics/kamera", "kde/kdegraphics/kcolorchooser", "kde/kdegraphics/kdegraphics-mobipocket", "kde/kdegraphics/kdegraphics-thumbnailers", "kde/kdegraphics/libs/libkdcraw", "kde/kdegraphics/libs/libkexiv2", "kde/kdegraphics/libs/libkface", "kde/kdegraphics/libs/libkgeomap", "kde/kdegraphics/libs/libkipi", "kde/kdegraphics/libs/libksane", "kde/kdegraphics/svgpart", "kde/kdemultimedia/audiocd-kio", "kde/kdemultimedia/ffmpegthumbs", "kde/kdemultimedia/kscd", "kde/kdemultimedia/libkcddb", "kde/kdemultimedia/libkcompactdisc", "kde/kdenetwork/kaccounts-integration", "kde/kdenetwork/kaccounts-providers", "kde/kdenetwork/kdenetwork-filesharing", "kde/kdenetwork/kio-extras", "kde/kdenetwork/kopete", "kde/kdenetwork/ktp-accounts-kcm", "kde/kdenetwork/ktp-approver", "kde/kdenetwork/ktp-auth-handler", "kde/kdenetwork/ktp-call-ui", "kde/kdenetwork/ktp-common-internals", "kde/kdenetwork/ktp-contact-list", "kde/kdenetwork/ktp-contact-runner", "kde/kdenetwork/ktp-desktop-applets", "kde/kdenetwork/ktp-filetransfer-handler", "kde/kdenetwork/ktp-kded-module", "kde/kdenetwork/ktp-send-file", "kde/kdenetwork/ktp-text-ui", "kde/kdenetwork/zeroconf-ioslave", "kde/kdesdk/dolphin-plugins", "kde/kdesdk/kcachegrind", "kde/kdesdk/kde-dev-scripts", "kde/kdesdk/kde-dev-utils", "kde/kdesdk/kdesdk-kioslaves", "kde/kdesdk/kdesdk-thumbnailers", "kde/kdesdk/libkomparediff2", "kde/kdesdk/poxml", "kde/kdeutils/kcharselect", "kde/kdeutils/kdebugsettings", "kde/kdeutils/kdf", "kde/kdeutils/kwalletmanager", "kde/kdeutils/print-manager", "kde/pim/akonadi", "kde/pim/akonadi-calendar", "kde/pim/akonadi-calendar-tools", "kde/pim/akonadi-contacts", "kde/pim/akonadi-import-wizard", "kde/pim/akonadi-mime", "kde/pim/akonadi-notes", "kde/pim/akonadi-search", "kde/pim/akonadiconsole", "kde/pim/calendarsupport", "kde/pim/eventviews", "kde/pim/grantlee-editor", "kde/pim/grantleetheme", "kde/pim/incidenceeditor", "kde/pim/kalarmcal", "kde/pim/kblog", "kde/pim/kcalcore", "kde/pim/kcalutils", "kde/pim/kcontacts", "kde/pim/kdav", "kde/pim/kdepim-addons", "kde/pim/kdepim-apps-libs", "kde/pim/kdepim-runtime", "kde/pim/kidentitymanagement", "kde/pim/kimap", "kde/pim/kldap", "kde/pim/kmail-account-wizard", "kde/pim/kmailtransport", "kde/pim/kmbox", "kde/pim/kmime", "kde/pim/kontactinterface", "kde/pim/kpimtextedit", "kde/pim/ksmtp", "kde/pim/ktnef", "kde/pim/libgravatar", "kde/pim/libkdepim", "kde/pim/libkgapi", "kde/pim/libkleo", "kde/pim/libksieve", "kde/pim/mailcommon", "kde/pim/mailimporter", "kde/pim/mbox-importer", "kde/pim/messagelib", "kde/pim/pim-data-exporter", "kde/pim/pim-sieve-editor", "kde/pim/pimcommon", "kde/pim/syndication", "kde/workspace/bluedevil", "kde/workspace/breeze", "kde/workspace/breeze-grub", "kde/workspace/breeze-gtk", "kde/workspace/breeze-plymouth", "kde/workspace/drkonqi", "kde/workspace/kactivitymanagerd", "kde/workspace/kde-cli-tools", "kde/workspace/kde-gtk-config", "kde/workspace/kdecoration", "kde/workspace/kdeplasma-addons", "kde/workspace/kgamma5", "kde/workspace/khotkeys", "kde/workspace/kinfocenter", "kde/workspace/kmenuedit", "kde/workspace/kscreen", "kde/workspace/kscreenlocker", "kde/workspace/ksshaskpass", "kde/workspace/ksysguard", "kde/workspace/kwallet-pam", "kde/workspace/kwayland-integration", "kde/workspace/kwin", "kde/workspace/kwrited", "kde/workspace/libkscreen", "kde/workspace/libksysguard", "kde/workspace/milou", "kde/workspace/oxygen", "kde/workspace/plasma-browser-integration", "kde/workspace/plasma-desktop", "kde/workspace/plasma-integration", "kde/workspace/plasma-nm", "kde/workspace/plasma-pa", "kde/workspace/plasma-tests", "kde/workspace/plasma-vault", "kde/workspace/plasma-workspace", "kde/workspace/plasma-workspace-wallpapers", "kde/workspace/plymouth-kcm", "kde/workspace/polkit-kde-agent-1", "kde/workspace/powerdevil", "kde/workspace/sddm-kcm", "kde/workspace/systemsettings", "kde/workspace/user-manager", "kde/workspace/xdg-desktop-portal-kde", "kde-build-metadata", "repo-management"]
