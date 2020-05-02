+++
date = "2020-05-01T10:04:54+01:00"
title = "Enable Mozilla Firefox and Thunderbird on wayland in Ubuntu 20.04"
tags = ["wayland", "linux", "ubuntu", "firefox", "thunderbird", "mozilla", "fractional scaling"]
categories = ["linux"]

+++
This guide will help you configure Fractional Scaling (later called FS) on ubuntu 20.04 and wayland session.

At the moment, ubuntu sees wayland users as 'just 1%'[^3], so feel pretty special if you choose this path :)

[^3]: [Enable fractional scaling toggle does not work](https://bugs.launchpad.net/ubuntu/+source/gnome-control-center/+bug/1871864)

To enable wayland session follow this doc: https://linuxconfig.org/how-to-enable-disable-wayland-on-ubuntu-20-04-desktop

Test if your current session is wayland based[^1]:

[^1]: https://unix.stackexchange.com/questions/202891/how-to-know-whether-wayland-or-x11-is-being-used

```bash
#Check your session ID
$ loginctl
$ loginctl show-session <SESSION_ID> -p Type

# or oneliner
$ loginctl show-session $(awk '/tty/ {print $1}' <(loginctl)) -p Type | awk -F= '{print $2}'

```

For example:
```bash
$ loginctl
SESSION  UID USER       SEAT  TTY
     12 1000 user seat0 tty2

1 sessions listed.
$ loginctl show-session 12 -p Type
Type=wayland

$ loginctl show-session $(awk '/tty/ {print $1}' <(loginctl)) -p Type | awk -F= '{print $2}'
wayland
```


To enable wayland FS, type in terminal:

```bash
$ gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer', 'x11-randr-fractional-scaling']"
```

Now, restart your current session by reloging or restarting your pc.

Go to 'Displays" -> "Scaling" and choose your drug. You should see: 100%, 125% 150% 175% and 200% options.

## Configuring Mozilla programs

### Firefox

#### Test
Firefox, by default, will open in the X11 mode, making the fonts blurry in the FS mode. To change it to native wayland for one time run, type:

```bash
$ MOZ_ENABLE_WAYLAND=1 firefox
```

#### Verify

To verify whether Wayland support is enabled, go to `about:support`, and check "Window protocol" information in the Graphics section (listed under Features) which says "x11" when running under XWayland and "wayland" when running as a Wayland client[^2].

[^2]: https://bugzilla.mozilla.org/show_bug.cgi?id=1507665

#### Enable as default

If you are happy with result, and would like to run firefox in wayland as default, you have to copy .desktop file of firefox to your home directory and change it accordingly:

```bash
$ cp /usr/share/applications/firefox.desktop ~/.local/share/applications/firefox.desktop
$ sed 's/Exec=firefox/Exec=env MOZ_ENABLE_WAYLAND=1 firefox/g' -i ~/.local/share/applications/firefox.desktop
```

### Thunderbird

You can repeat that process for thunderbird.

#### Test

```bash
$ MOZ_ENABLE_WAYLAND=1 thunderbird
```

#### Enable as default

and if your are happy with result, save the setting as:

```bash
$ cp /usr/share/applications/thunderbird.desktop ~/.local/share/applications/thunderbird.desktop
$ sed 's/Exec=thunderbird/Exec=env MOZ_ENABLE_WAYLAND=1 thunderbird/g' -i ~/.local/share/applications/thunderbird.desktop
```

## Debug notes

To debug .desktop file install `dex` and run:

```bash
dex ~/.local/share/applications/firefox.desktop
```

## Note:

This is my first post, written in English, if you see some typos or errors, please let me know.
The code is opensource and available here: https://github.com/pszypowicz/blog