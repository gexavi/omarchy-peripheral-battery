#!/bin/bash
# Install the peripheral-battery system service.
#
#   sudo ./install.sh
#
# Copies the reader into /usr/local/lib (root-owned, so code that runs as root
# cannot be modified from your user account), installs the systemd units and
# starts the timer. Re-run it after updating the plugin to update the service.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
lib=/usr/local/lib/peripheral-battery
units=/etc/systemd/system

if [[ $EUID -ne 0 ]]; then
  echo "This installs a system service and must run as root: sudo $0" >&2
  exit 1
fi

if [[ ! -x /usr/bin/python3 ]]; then
  echo "python3 is required (/usr/bin/python3 not found)." >&2
  exit 1
fi

install -d -m 0755 -o root -g root "$lib"
install -m 0755 -o root -g root "$here/peripheral-battery" "$lib/peripheral-battery"
install -m 0644 -o root -g root "$here/peripheral-battery.service" "$units/peripheral-battery.service"
install -m 0644 -o root -g root "$here/peripheral-battery.timer" "$units/peripheral-battery.timer"

systemctl daemon-reload
# Start from fresh readings so nothing recorded by a previous version lingers,
# and probe every device again.
rm -f /run/peripheral-battery/status.json /run/peripheral-battery/probe-state.json
systemctl enable peripheral-battery.timer
# Restart rather than start, so an update applies new timer settings.
systemctl restart peripheral-battery.timer
systemctl start peripheral-battery.service

echo
echo "Installed. Current readings (/run/peripheral-battery/status.json):"
cat /run/peripheral-battery/status.json
