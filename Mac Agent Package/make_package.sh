#!/bin/bash

cp -f ./sync.conf ./scripts/sync.conf
chmod +x ./scripts/preinstall
chmod +x ./scripts/postinstall
hdiutil unmount -force -quiet "/Volumes/Resilio Connect Agent"/
hdiutil attach Resilio-Connect-Agent.dmg 

pkgbuild --install-location /Applications --identifier com.resilio.agent.pkg.app --version 1.1 --scripts ./scripts --component /Volumes/Resilio\ Connect\ Agent/Resilio\ Connect\ Agent.app ./resilio-connect-agent.pkg

hdiutil unmount "/Volumes/Resilio Connect Agent"/

exit 0




