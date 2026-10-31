#!/bin/bash
# One-time prerequisite, pasted into Terminal INSIDE the vanilla macOS VM.
set -eo pipefail
[ "$(uname -s)" = Darwin ] || { echo 'Run inside the macOS VM.' >&2; exit 1; }
case "$(sysctl -n hw.model)" in
    VirtualMac*) ;;
    *) echo 'Refusing to install the guest agent outside a macOS VM.' >&2; exit 1 ;;
esac
[ "$(id -un)" = admin ] || { echo 'Run as the VM image user admin.' >&2; exit 1; }
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cd "$stage"
curl -qfL --max-time 300 https://github.com/openai/tart-guest-agent/releases/download/v0.15.0/tart-guest-agent-darwin-all.tar.gz -o agent.tar.gz
printf '%s\n' 'eb47f402f18e742a8ea96344115ca776179f9c4c67494bc0c46a10a68db280b7  agent.tar.gz' | shasum -a 256 -c -
tar -xzf agent.tar.gz
sudo -n launchctl bootout system/local.dotfiles.tart-rpc 2>/dev/null || true
sudo -n mkdir -p /usr/local/libexec
sudo -n install -m 755 tart-guest-agent /usr/local/libexec/dotfiles-tart-guest-agent
sudo -n tee /Library/LaunchDaemons/local.dotfiles.tart-rpc.plist >/dev/null <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.dotfiles.tart-rpc</string>
<key>UserName</key><string>admin</string>
<key>ProgramArguments</key><array>
<string>/usr/local/libexec/dotfiles-tart-guest-agent</string><string>--run-rpc</string>
</array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>WorkingDirectory</key><string>/Users/admin</string>
<key>EnvironmentVariables</key><dict>
<key>HOME</key><string>/Users/admin</string>
<key>USER</key><string>admin</string>
<key>LOGNAME</key><string>admin</string>
<key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin</string>
</dict>
<key>StandardOutPath</key><string>/tmp/dotfiles-tart-rpc.log</string>
<key>StandardErrorPath</key><string>/tmp/dotfiles-tart-rpc.log</string>
</dict></plist>
PLIST
sudo -n chown root:wheel /Library/LaunchDaemons/local.dotfiles.tart-rpc.plist
sudo -n chmod 644 /Library/LaunchDaemons/local.dotfiles.tart-rpc.plist
sudo -n launchctl bootstrap system /Library/LaunchDaemons/local.dotfiles.tart-rpc.plist
sync
echo 'Guest agent installed. VM preparation on the host can now continue.'
