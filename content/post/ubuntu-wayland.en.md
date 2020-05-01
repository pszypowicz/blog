+++
date = "2020-05-01T10:04:54+01:00"
title = "Enable Mozilla Firefox and Thunderbird on wayland in Ubuntu 20.04"
tags = ["wayland", "linux", "ubuntu", "firefox", "thunderbird", "mozilla", "fractional scaling"]
categories = ["linux"]

+++
This guild will help you configure Fractional Scaling (later called FS) on ubuntu 20.04 and wayland session.


Unfortunately, ubuntu sees wayland users as 'just 1%', so feel pretty special if you choose this path :)

To enable wayland FS, type in terminal

```bash
$ gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer', 'x11-randr-fractional-scaling']"
```

Now, restart your current session by reloging or restarting your pc.

Go to 'Displays" -> "Scaling" and choose your drug. You should see: 100%, 125% 150% 175% and 200% options.

## Configuring Mozilla programs

Firefox, by default, will open in the X11 mode, making the fonts blurry in the FS mode. To change it to wayland, run:

```bash
$ MOZ_ENABLE_WAYLAND=1 firefox
```

If you are happy with outcome, and would like to run firefox in wayland as default, you have to copy .desktop file of firefox to your user folder and change it accordingly:

```bash
$ cp /usr/share/applications/firefox.desktop ~/.local/share/applications/firefox.desktop
$ sed 's/Exec=firefox/Exec=env MOZ_ENABLE_WAYLAND=1 firefox/g' -i ~/.local/share/applications/firefox.desktop
```

You can repeat that process for thunderbird.

Test it with
```bash
$ MOZ_ENABLE_WAYLAND=1 thunderbird
```

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

## Links

[Enable fractional scaling toggle does not work](https://bugs.launchpad.net/ubuntu/+source/gnome-control-center/+bug/1871864)

## Note:

This is my first post, written in English, if you see some typos or errors, please let me know.
The code is opensource and available here: https://github.com/pszypowicz/hugotechhaven