#!/bin/bash

read -r -d '' SERVICE_FILE_CONTENT << 'EOF'
[Unit]
Description=Resilio multi-agent service %i
Documentation=https://connect.resilio.com
After=network.target network-online.target
 
[Service]
Type=forking
UMask=0002
Restart=on-failure
PermissionsStartOnly=true
 
LimitNOFILE=16384
 
User=rslagent
Group=rslagent
Environment="AGENT_USER=rslagent"
Environment="AGENT_GROUP=rslagent"
 
Environment="AGENT_LIB_DIR=/var/lib/resilio-agent-%i"
Environment="AGENT_CONF_DIR=/etc/resilio-agent"
 
PIDFile=/var/lib/resilio-agent-%i/sync.pid
 
ExecStartPre=/bin/mkdir -p ${AGENT_LIB_DIR}
ExecStartPre=/bin/chown -R ${AGENT_USER}:${AGENT_GROUP} ${AGENT_LIB_DIR}
ExecStartPre=/bin/bash -c "echo \"{\\\"device_name\\\": \\\"$(hostname)-%i\\\", \\\"listening_port\\\": $((3840+%i))}\" > \"${AGENT_CONF_DIR}/sync-%i.conf\" "
ExecStart=/usr/bin/rslagent --config ${AGENT_CONF_DIR}/sync.conf --storage ${AGENT_LIB_DIR} --config ${AGENT_CONF_DIR}/sync-%i.conf
ExecStartPost=/bin/sleep 1
 
[Install]
WantedBy=multi-user.target
EOF

# Ensure script runs as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root."
  exit 1
fi

# Check if resilio_agent package is installed
if command -v dpkg &> /dev/null; then
  if ! dpkg -l | grep -q "resilio-agent"; then
    echo "Error: resilio_agent package is not installed."
    exit 1
  fi
elif command -v rpm &> /dev/null; then
  if ! rpm -qa | grep -q "resilio-agent"; then
    echo "Error: resilio_agent package is not installed."
    exit 1
  fi
else
  echo "Error: Unable to determine package manager."
  exit 1
fi

# Check if sync.conf exists
if [ ! -f "/etc/resilio-agent/sync.conf" ]; then
  echo "Error: /etc/resilio-agent/sync.conf does not exist."
  exit 1
fi

# Display help if no parameters supplied
if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <command> [parameter]"
  echo "Commands:"
  echo "  init                 Create the .service file in /lib/systemd/system"
  echo "  start X              Start X resilio multi-agent services"
  echo "  stop                 Stop all running resilio multi-agent services"
  echo "  enable X             Enable X resilio multi-agent services"
  echo "  disable              Disable all enabled resilio multi-agent services"
  exit 0
fi

COMMAND=$1
PARAM=$2

case $COMMAND in
  init)
    echo "Creating resilio-multi-agent@.service file..."
    echo "$SERVICE_FILE_CONTENT" > /lib/systemd/system/resilio-multi-agent@.service
    systemctl daemon-reload
    echo "Service file created successfully."
    ;;

  start)
    if [[ -z $PARAM || ! $PARAM =~ ^[0-9]+$ ]]; then
      echo "Error: You must specify the number of agents to start."
      exit 1
    fi
    if [[ $PARAM -eq 0 ]]; then
      echo "Error: The amount of agents cannot be zero."
      exit 1
    fi
    for ((i=1; i<=PARAM; i++)); do
      echo "Starting resilio-multi-agent@$i..."
      systemctl start resilio-multi-agent@$i
    done
    ;;

  stop)
    echo "Stopping all running resilio-multi-agent services..."
    for service in $(systemctl list-units --type=service | grep resilio-multi-agent@ | awk '{print $1}'); do
      echo "Stopping $service..."
      systemctl stop $service
    done
    ;;

  enable)
    if [[ -z $PARAM || ! $PARAM =~ ^[0-9]+$ ]]; then
      echo "Error: You must specify the number of agents to enable."
      exit 1
    fi
    if [[ $PARAM -eq 0 ]]; then
      echo "Error: The amount of agents cannot be zero."
      exit 1
    fi
    for ((i=1; i<=PARAM; i++)); do
      echo "Enabling resilio-multi-agent@$i..."
      systemctl enable resilio-multi-agent@$i
    done
    ;;

  disable)
    echo "Disabling all enabled resilio-multi-agent services..."
    for service in $(systemctl list-units --type=service | grep resilio-multi-agent@ | awk '{print $1}'); do
      echo "Disabling $service..."
      systemctl disable $service
    done
    ;;

  *)
    echo "Error: Invalid command."
    echo "Run $0 with no parameters to see available commands."
    exit 1
    ;;
esac
