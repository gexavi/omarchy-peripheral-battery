#!/bin/bash
# Remove the peripheral-battery system service and everything install.sh created.
#
#   sudo ./uninstall.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "This removes a system service and must run as root: sudo $0" >&2
  exit 1
fi

systemctl disable --now peripheral-battery.timer 2>/dev/null || true
systemctl stop peripheral-battery.service 2>/dev/null || true
rm -f /etc/systemd/system/peripheral-battery.service /etc/systemd/system/peripheral-battery.timer
rm -rf /usr/local/lib/peripheral-battery /run/peripheral-battery
systemctl daemon-reload

echo "peripheral-battery service removed."
