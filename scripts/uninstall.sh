#!/usr/bin/env bash
# Manual escape hatch: removes the helper and guarantees normal sleep is restored.
set -euo pipefail
LABEL="io.github.mahit-c.ajar.helper"
sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
sudo rm -f "/Library/PrivilegedHelperTools/$LABEL" "/Library/LaunchDaemons/$LABEL.plist"
sudo rm -rf "/Library/Application Support/Ajar"
sudo pmset -a disablesleep 0
pmset -g | grep SleepDisabled
