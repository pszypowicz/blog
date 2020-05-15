+++
date = "2020-05-15T10:04:54+01:00"
title = "Testing and signing kernel for ubuntu 20.04"
tags = ["kernel", "linux", "ubuntu", "secure boot"]
categories = ["linux"]

+++
Disclaimer!

This a information regarding mainline kernel, copied from the ubuntu wiki:

_By default, Ubuntu systems run with the Ubuntu kernels provided by the Ubuntu repositories. However it is handy to be able to test with unmodified upstream kernels to help locate problems in Ubuntu kernel patches, or to confirm that upstream has fixed a specific issue. To this end we now offer select upstream kernel builds. These kernels are made from unmodified kernel source but using the Ubuntu kernel configuration files. These are then packaged as Ubuntu .deb files for simple installation, saving you the time of compiling kernels, and debugging build issues._

_These kernels are not supported and are not appropriate for production use._




# Install kernel from PPA mainline

For detailed instruction follow this link: https://wiki.ubuntu.com/Kernel/MainlineBuilds

BUT, there is a semi-automated way to install the version of kernel of your choice:

For more information and installation procedure follow instruction on this site: https://github.com/pimlie/ubuntu-mainline-kernel.sh

## Using ubuntu-mainline-kernel to install rc release

For testing the rc release of the kernel, do:

```bash
sudo ubuntu-mainline-kernel.sh --rc -i
```

## MOK keys

If you are using ubuntu 20.04 and during installation
1. Had "Secure Boot" enabled
2. Choosed to install 3rd party drivers

There is a chance you were asked to enroll new key in MOK, which is automatically used to sign new
kernel modules.

Those keys are available in location

```bash
$ ls /var/lib/shim-signed/mok/*
/var/lib/shim-signed/mok/MOK.der  /var/lib/shim-signed/mok/MOK.priv
```

To use the to sign kernel as well we have to transform the MOK.der key to the PEM format and to do so type:

```bash
$ cd /var/lib/shim-signed/mok
$ sudo openssl x509 -in MOK.der -inform DER -outform PEM -out MOK.pem
```

## Sign your kernel

1. Sign the vmlinuz kernel of your choice

    ```bash
    sudo sbsign --key /var/lib/shim-signed/mok/MOK.priv --cert /var/lib/shim-signed/mok/MOK.pem /boot/vmlinuz-[KERNEL-VERSION]-generic --output /boot/vmlinuz-[KERNEL-VERSION]-generic.signed
    ```

2. Copy the initram to create a pair with signed vmlinuz image

    ```bash
    $ sudo cp /boot/initrd.img-[KERNEL-VERSION]-generic{,.signed}
    ```

3. Update GRUB

    ```bash
    $ sudo update-grub
    ```

## Rebot and test

After reboot choose in grub entry of the signed kernel, and if system boots up properly and you want to keep the configuration, you can overwrite unsigned version of your kernel and call `update-grub` again

```bash
sudo mv /boot/vmlinuz-[KERNEL-VERSION]-generic{.signed,}
sudo mv /boot/initrd.img-[KERNEL-VERSION]-generic{.signed,}
sudo update-grub
```