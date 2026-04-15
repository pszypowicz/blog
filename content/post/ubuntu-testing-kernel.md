+++
title       = "Testing and signing kernel for Ubuntu 20.04"
date        = "2020-05-15T10:04:54+01:00"
description = "Install a mainline kernel on Ubuntu 20.04 via ubuntu-mainline-kernel.sh and sign it with your MOK key so Secure Boot keeps working."
tags        = ["kernel", "linux", "ubuntu", "secure boot"]
categories  = ["linux"]
+++

> **Disclaimer.** This is about mainline kernel builds, summarized from the Ubuntu wiki:
>
> By default, Ubuntu systems run with the Ubuntu kernels provided by the Ubuntu repositories. However it is handy to test unmodified upstream kernels to help locate problems in Ubuntu kernel patches, or to confirm that upstream has fixed a specific issue. These kernels are not supported and are not appropriate for production use.

## Install a mainline kernel via PPA

Detailed official instructions: <https://wiki.ubuntu.com/Kernel/MainlineBuilds>.

There is a semi-automated wrapper that makes this much less painful:
<https://github.com/pimlie/ubuntu-mainline-kernel.sh>

### Install an RC release

```bash
sudo ubuntu-mainline-kernel.sh --rc -i
```

## MOK keys (Secure Boot)

If you installed Ubuntu 20.04 with Secure Boot enabled **and** chose to install third-party drivers, you were probably asked to enroll a new key in MOK. That key is then used to sign new kernel modules automatically. It lives at:

```bash
$ ls /var/lib/shim-signed/mok/
MOK.der  MOK.priv
```

To sign the kernel itself you need the key in PEM form:

```bash
$ cd /var/lib/shim-signed/mok
$ sudo openssl x509 -in MOK.der -inform DER -outform PEM -out MOK.pem
```

## Sign the kernel

1. Sign the `vmlinuz` of your choice:

   ```bash
   sudo sbsign --key /var/lib/shim-signed/mok/MOK.priv \
               --cert /var/lib/shim-signed/mok/MOK.pem \
               /boot/vmlinuz-[KERNEL-VERSION]-generic \
               --output /boot/vmlinuz-[KERNEL-VERSION]-generic.signed
   ```

2. Copy the initrd so it pairs with the signed vmlinuz:

   ```bash
   sudo cp /boot/initrd.img-[KERNEL-VERSION]-generic{,.signed}
   ```

3. Update GRUB:

   ```bash
   sudo update-grub
   ```

## Reboot and test

Pick the `.signed` entry in GRUB. If the system boots cleanly and you want to keep the configuration, overwrite the unsigned files with the signed ones and run `update-grub` again:

```bash
sudo mv /boot/vmlinuz-[KERNEL-VERSION]-generic{.signed,}
sudo mv /boot/initrd.img-[KERNEL-VERSION]-generic{.signed,}
sudo update-grub
```
