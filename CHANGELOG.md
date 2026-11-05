# Changelog

## [Unreleased]

### Added
- Menu bar app that keeps the Mac awake with the lid closed (`pmset disablesleep`) via a minimal root helper
- Session durations from 15 minutes to 8 hours, or indefinitely
- Safety: battery temperature limit with early warning, macOS thermal state, low battery, stop when unplugged
- Helper fail-safes: restores sleep on app disconnect, missed heartbeat, 55 °C, critical thermal state, and after a reboot mid-session
- Re-applies on power-source changes
- Locks the screen when the lid closes during a session (skipped in clamshell mode with an external display)
- Welcome window, Settings window (opens when Ajar is reopened), diagnostics export
