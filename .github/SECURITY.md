# Security policy

## Supported versions

Only the latest release gets security fixes. Sysbar checks for updates once a day and can install
them itself, so please update before reporting.

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately instead, either way:

- with GitHub's [Report a vulnerability](https://github.com/Atanur/sysbar/security/advisories/new)
  form, which only the maintainer and you can see, or
- by email to **atanur.ozkaldim@gmail.com**.

Include:

- the Sysbar version (Settings › About) and macOS version,
- what an attacker can do, and what they need first (local access, a malicious server, the same network),
- steps or a proof of concept to reproduce it.

You will get a reply within a week. Once the problem is confirmed, a fix is released as soon as it
is ready, and the release notes credit you unless you would rather not be named.

## What Sysbar can reach

These are the parts where a weakness would matter most, and what each one is allowed to do.

- **The helper.** `SysbarFanHelper` is a launch daemon that runs as root, only after you approve it
  in System Settings. It accepts connections only from a copy of Sysbar signed by the same
  developer, and it can do three things: set fan speeds within each fan's own limits, give the fans
  back to macOS, and keep a laptop awake with its lid closed. Manual fan speed lapses unless Sysbar
  renews it every few seconds, so the fans return to automatic if Sysbar quits or crashes.
- **Remote devices.** Sysbar runs the system `ssh` with your own keys or ssh-agent; it stores no
  passwords and no keys, only a key file's path. Host and user names are checked so they can never
  be read as ssh options. The script sent to a server only reads; it changes nothing there.
- **Finding devices.** Sysbar listens for Macs that announce Remote Login on the local network and
  reads `tailscale status`. It connects to nothing until you add a device.
- **Updates.** Sysbar asks GitHub for the latest release. Before replacing itself, it checks that
  the downloaded app has the same identifier and developer signature as the running one and the
  version that was offered; a copy that does not match is never installed.

Sysbar sends nothing about your Mac anywhere.
