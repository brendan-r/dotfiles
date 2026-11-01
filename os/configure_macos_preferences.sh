#!/bin/bash

# Apply personal desktop, Finder, text and workspace settings on macOS.
# script_directory is the os/ directory in this checkout.
# configuration_args contains options not consumed by setup.
# shellcheck source=os/lib/setup.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/setup.sh" || exit 1
setup "$@"
[ "${#configuration_args[@]}" -eq 0 ] || exit 2

#  - - -  Dock  - - -

set_dock_preferences() {

    # Automatically hide the Dock when it is not in use.
    /usr/bin/defaults write com.apple.dock autohide -bool true

    # Minimize windows using the scale effect.
    /usr/bin/defaults write com.apple.dock mineffect -string "scale"

    # Keep desktops in their chosen order instead of sorting by recent use.
    /usr/bin/defaults write com.apple.dock mru-spaces -bool false

    # Set the Dock icon size to match the current Mac.
    /usr/bin/defaults write com.apple.dock tilesize -float 51

}

#  - - -  Finder, text and widgets  - - -

set_desktop_preferences() {

    # Show the current path and complete filenames in Finder.
    /usr/bin/defaults write com.apple.finder ShowPathbar -bool true
    /usr/bin/defaults write NSGlobalDomain AppleShowAllExtensions -bool true

    # Leave spelling as typed instead of correcting it automatically.
    /usr/bin/defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

    # Hide widgets on the desktop and when using Stage Manager.
    /usr/bin/defaults write com.apple.WindowManager StandardHideWidgets -bool true
    /usr/bin/defaults write com.apple.WindowManager StageManagerHideWidgets -bool true

}

#  - - -  Motion  - - -

read_motion_status() {

    /usr/bin/osascript <<'APPLESCRIPT'
use framework "AppKit"
return current application's NSWorkspace's sharedWorkspace()'s accessibilityDisplayShouldReduceMotion() as boolean
APPLESCRIPT

}

motion_is_reduced() {

    # Ask macOS for the effective setting, not just a stored preference key.
    local current
    current=$(read_motion_status) || return 1
    [ "$current" = true ]

}

set_motion_preferences() {

    # A protected preference may already have been enabled in System Settings.
    if motion_is_reduced; then
        return 0
    fi

    # Reduce motion effects in the macOS interface when macOS permits writing.
    /usr/bin/defaults write com.apple.universalaccess reduceMotion -bool true || return 1

    # A successful write does not necessarily change the effective setting.
    motion_is_reduced

}

#  - - -  Numbered desktops  - - -

set_desktop_shortcut() {

    local shortcut_id=$1 key_code=$2

    # Add this shortcut without replacing the other AppleSymbolicHotKeys entries.
    # 65535 means no character equivalent; 262144 is the Control modifier.
    /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add \
        "$shortcut_id" "<dict>
            <key>enabled</key><true/>
            <key>value</key><dict>
                <key>parameters</key><array>
                    <integer>65535</integer>
                    <integer>$key_code</integer>
                    <integer>262144</integer>
                </array>
                <key>type</key><string>standard</string>
            </dict>
        </dict>"

}

set_desktop_shortcuts() {

    # Enable Control-1 through Control-0 for desktops 1 through 10.
    # Each pair is the macOS shortcut ID and the original virtual key code.
    # These shortcuts do not create desktops; add those in Mission Control.

    set_desktop_shortcut 118 18    # Control-1: desktop 1.
    set_desktop_shortcut 119 19    # Control-2: desktop 2.
    set_desktop_shortcut 120 20    # Control-3: desktop 3.
    set_desktop_shortcut 121 21    # Control-4: desktop 4.
    set_desktop_shortcut 122 23    # Control-5: desktop 5.
    set_desktop_shortcut 123 22    # Control-6: desktop 6.
    set_desktop_shortcut 124 26    # Control-7: desktop 7.
    set_desktop_shortcut 125 28    # Control-8: desktop 8.
    set_desktop_shortcut 126 25    # Control-9: desktop 9.
    set_desktop_shortcut 127 29    # Control-0: desktop 10.

}

#  - - -  Solid grey desktop background  - - -

set_desktop_background() {

    local mode=$1 background=$2

    # macOS exposes its desktop-image API through AppleScript's AppKit bridge.
    # Validation only checks for screens; it does not change the wallpaper.
    # The bundled PNG is the previous solid grey: sRGB 0.5 / 0.5 / 0.5.
    /usr/bin/osascript - "$mode" "$background" <<'APPLESCRIPT'
use framework "AppKit"

on run arguments
    set screens to current application's NSScreen's screens()
    if (screens's |count|() as integer) is 0 then
        error "Set the background from a logged-in graphical session."
    end if
    if item 1 of arguments is "validate" then return

    set imageURL to current application's NSURL's fileURLWithPath:(item 2 of arguments)
    set workspace to current application's NSWorkspace's sharedWorkspace()
    repeat with screen in screens
        set {applied, failure} to workspace's setDesktopImageURL:imageURL forScreen:screen options:(current application's NSDictionary's dictionary()) |error|:(reference)
        if not applied then error (failure's localizedDescription() as text)
    end repeat
end run
APPLESCRIPT

}

#  - - -  Apply the preferences  - - -

# Check the platform and graphical session before changing any settings.
[ "$(uname -s)" = Darwin ] || {
    printf 'These preferences require macOS.\n' >&2
    exit 1
}

background="$script_directory/os_x/grey.png"
[ -f "$background" ] || {
    printf 'Missing desktop background: %s\n' "$background" >&2
    exit 1
}

set_desktop_background validate "$background"

# Retain original domains in the run log directory when invoked by the installer.
# Standalone runs keep their exports in a new temporary directory.
run_directory=${DOTFILES_RUN_DIRECTORY:-}
if [ -z "$run_directory" ]; then
    run_directory=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-preferences.XXXXXX")
fi
for domain in com.apple.dock com.apple.finder com.apple.WindowManager NSGlobalDomain \
    com.apple.universalaccess com.apple.symbolichotkeys; do
    if /usr/bin/defaults read "$domain" >/dev/null 2>&1; then
        /usr/bin/defaults export "$domain" "$run_directory/macos-preferences.$domain.before.plist"
    fi
done
printf 'Previous settings saved in %s\n' "$run_directory"

set_dock_preferences
set_desktop_preferences
set_desktop_shortcuts
set_desktop_background apply "$background"

# Recent macOS versions may protect the motion preference from terminal writes.
# Apply the other settings first, then report failure with a manual remedy.
if ! set_motion_preferences; then
    printf 'Could not enable Reduce Motion. In System Settings, open Accessibility > Display and enable Reduce motion, then rerun.\n' >&2
    printf 'Terminal access may require Full Disk Access in Privacy & Security.\n' >&2
    printf 'The other desktop preferences and background were applied.\n' >&2
    exit 1
fi

printf 'Preferences saved. Log out and back in to activate all changes.\n'
printf 'Background applied to connected displays in the current Space.\n'
