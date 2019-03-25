# Mac Agent Package

This folder contains components to create an OS X .pkg package. The package have next features comparing to plain DMG:
* allows to pre-package your sync.conf together with installer into a single file
* shows user-friendly installer
* registers Connect Agent as OS X LaunchAgent with automatic startup on user login

Minimal set of files that should be present in scirpt directory to create a package:
* make_package.sh
* scripts (folder containing deployment scripts)
* Resilio-Connect-Agent.dmg (use the version you want to deploy)
* sync.conf (download from your management console)

Once all files are present, run "make_package.sh" from the terminal. The package will appear in the same folder. Please note, that package goes unsigned and requires user to right-click (or ctrl-click) on the package to get it installed.

