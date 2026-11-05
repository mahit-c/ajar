# Security Policy

Ajar installs a helper that runs as root, so security reports are taken seriously.

## Reporting a vulnerability

Please **don't open a public issue**. Report privately through GitHub's
[security advisory form](https://github.com/mahit-c/ajar/security/advisories/new).

Include the Ajar version, your macOS version, and steps to reproduce. You should get a response within a few days.

## Scope

Of most interest:

- Any way for a process other than Ajar to make the helper act
- Any way to make the helper run commands other than `pmset -a disablesleep 0|1`
- Any way a session can leave the Mac unable to sleep after Ajar quits, crashes or is uninstalled

## Known limitation (beta)

Until releases are signed with a Developer ID, the helper verifies connecting apps by bundle identifier only. Signed releases pin the Apple Team ID as well. Unsigned beta builds are for testing only.
