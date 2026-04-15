+++
title       = "Enable Mozilla Firefox and Thunderbird on Wayland in Ubuntu 20.04"
date        = "2020-05-01T10:04:54+01:00"
description = "Turn on Wayland fractional scaling on Ubuntu 20.04 and make Firefox and Thunderbird render natively instead of going through XWayland."
tags        = ["wayland", "linux", "ubuntu", "firefox", "thunderbird", "fractional-scaling"]
categories  = ["linux"]
+++

This guide walks through turning on Wayland fractional scaling (FS) on Ubuntu 20.04 and then pointing Firefox and Thunderbird at it natively.

## Wayland

At the time of writing Ubuntu counted Wayland users as "less than 1%"[^1]. Feel special.

[^1]: <https://bugs.launchpad.net/ubuntu/+source/gnome-control-center/+bug/1871864>

### Enable

Follow <https://linuxconfig.org/how-to-enable-disable-wayland-on-ubuntu-20-04-desktop>.

### Test

**GUI.** `Settings -> About -> Windowing system`.

**CLI.** Check whether your current session is a Wayland one[^2]:

[^2]: <https://unix.stackexchange.com/questions/202891/how-to-know-whether-wayland-or-x11-is-being-used>

```bash
# Check your session ID
$ loginctl
$ loginctl show-session <SESSION_ID> -p Type

# or as a one-liner
$ loginctl show-session $(awk '/tty/ {print $1}' <(loginctl)) -p Type | awk -F= '{print $2}'
```

For example:

```bash
$ loginctl
SESSION  UID USER       SEAT  TTY
     12 1000 user       seat0 tty2

1 sessions listed.

$ loginctl show-session 12 -p Type
Type=wayland
```

## Fractional scaling

To enable Wayland FS:

```bash
$ gsettings set org.gnome.mutter experimental-features \
    "['scale-monitor-framebuffer', 'x11-randr-fractional-scaling']"
```

Log out and back in (or reboot). `Displays -> Scaling` now offers 100%, 125%, 150%, 175%, and 200%.

## Firefox and Thunderbird on Wayland

### Test it once

Firefox opens in X11 mode by default, which makes fonts blurry under fractional scaling. Run it once in Wayland mode:

```bash
$ MOZ_ENABLE_WAYLAND=1 firefox
```

### Verify

Open `about:support` and check **Window protocol** under Graphics / Features. It reads `x11` under XWayland and `wayland` as a native Wayland client[^3].

[^3]: <https://bugzilla.mozilla.org/show_bug.cgi?id=1507665>

### Make it the default

Copy the `.desktop` file into your user directory and patch it:

```bash
$ cp /usr/share/applications/firefox.desktop ~/.local/share/applications/firefox.desktop
$ sed -i 's/Exec=firefox/Exec=env MOZ_ENABLE_WAYLAND=1 firefox/g' \
    ~/.local/share/applications/firefox.desktop
```

Same drill for Thunderbird:

```bash
$ MOZ_ENABLE_WAYLAND=1 thunderbird
$ cp /usr/share/applications/thunderbird.desktop ~/.local/share/applications/thunderbird.desktop
$ sed -i 's/Exec=thunderbird/Exec=env MOZ_ENABLE_WAYLAND=1 thunderbird/g' \
    ~/.local/share/applications/thunderbird.desktop
```

## Debugging a `.desktop` file

```bash
$ sudo apt install dex
$ dex ~/.local/share/applications/firefox.desktop
```
