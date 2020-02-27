#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: deploy_agent <sync.conf>"
    exit 1
fi

sync_conf=$1
newuser=resilioagent 
group_id=20
maxid=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -ug | tail -1)
newid=$((maxid+1))
newpass=resilioagentpass
launchd_plist=/Library/LaunchDaemons/com.resilio.agent.plist
storage=/Users/$newuser/Library/Application\ Support/Resilio\ Connect\ Agent
start_script=$storage/Resilio_Agent.sh

echo "Creating \"$newuser\" user as part of GID \"$group_id\""

id -u $newuser >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "User \"$newuser\" already exists. Please remove it with \"sudo dscl . delete /Users/$newuser\" command if you no longer need it."
    #echo "User \"$newuser\" already exists, cleaning it up automatically"
    #sudo dscl . delete /Users/$newuser
    #sudo rm -r /Users/$newuser
    exit 1
fi

sudo dscl . -create /Users/$newuser
sudo dscl . -create /Users/$newuser UserShell /bin/bash
sudo dscl . -create /Users/$newuser UniqueID $newid
sudo dscl . -create /Users/$newuser PrimaryGroupID $newid
sudo dscl . -create /Users/$newuser NFSHomeDirectory /Users/$newuser
sudo dscl . -create /Users/$newuser Password $newpass
sudo dscl . -create /Users/$newuser RealName "Resilio Agent User"
sudo dscl . -append /Groups/staff GroupMembership resilioagent

echo "Creating storage folder"

sudo mkdir -p "$storage"

sudo cp "$sync_conf" "$storage/sync.conf"
sudo chown -R $newuser:$group_id "$storage"
sudo chown -R $newuser:$group_id "/Users/$newuser"
sudo chmod -R 775 "/Users/$newuser"

echo "Creating start script for Resilio Agent"

sudo tee "$start_script" << EOL
#!/bin/bash
sleep 90
/Applications/Resilio\ Connect\ Agent.app/Contents/MacOS/Resilio\ Connect\ Agent --config /Users/$newuser/Library/Application\ Support/Resilio\ Connect\ Agent/sync.conf
EOL

sudo chmod a+x "$start_script"
sudo chown $newuser:$group_id "$start_script"

echo "Creating next property list for LaunchDaemon"

sudo tee $launchd_plist << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "–//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>Label</key>
<string>com.resilio.agent</string>
<key>ProgramArguments</key>
<array>
<string>$start_script</string>
</array>
<key>RunAtLoad</key>
<true/>
<key>KeepAlive</key>
<true/>
<key>UserName</key>
<string>$newuser</string>
<key>Umask</key>
<integer>2</integer>
</dict>
</plist>
EOL

echo "Cleaning quarantine which may prevent Agent from startup"

sudo xattr -rc  /Applications/Resilio\ Connect\ Agent.app/

echo "Loading agent as daemon"
sudo launchctl load -w $launchd_plist
