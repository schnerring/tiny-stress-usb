# tiny-stress-usb

Tool to create a bootable USB device, including a minimal [Tiny Core Linux](http://tinycorelinux.net/) installation and various stress testing tools.

## Purpose

When building a new [FreeNAS](https://www.freenas.org/) system, I was looking for ways to test the stability of the hardware.

I wanted a bootable, ready-to-use environment that included everything I needed to burn-in a new system.

Most inspiring were the following resources, found in the iXsystems Community's [Forums](https://www.ixsystems.com/community/) and [Resources](https://www.ixsystems.com/community/resources/) sections:

* [github.com/Spearfoot/disk-burnin-and-testing](https://github.com/Spearfoot/disk-burnin-and-testing)
* [Hard Drive Burn-in Testing](https://www.ixsystems.com/community/resources/hard-drive-burn-in-testing.92/)
* [Building, Burn-In, and Testing your FreeNAS system](https://www.ixsystems.com/community/threads/building-burn-in-and-testing-your-freenas-system.17750/)

## Requirements

* POSIX compatible shell
* Must be run as `root`
* Required software packages:
  * `basename`
  * `blkid` to query partition UUID
  * `cp`
  * `dirname`
  * `git`: clone repositories
  * `grep`
  * `grub-install` to install GRUB
  * `ln`: create symbolic links
  * `lsblk` to check if USB device
  * `md5sum` to validate downloads
  * `mkdir` to create directories
  * `mkfs.ext2` to create ext2 file system
  * `mkfs.fat` to create FAT32 file system
  * `mksquashfs` to package custom Tiny Core extensions
  * `mount` to mount partitions
  * `partprobe` to re-read partition table
  * `sed` to search and replace in files
  * `sgdisk` for partitioning
  * `tee` for file logging
  * `wget` to download software

## Bundled Tiny Core Extensions

* `e2fsprogs`: `badblocks`
* `kmaps`: `alternative keyboard layouts`
* `smartmontools`: `smartctl`
* `screen`: `badblocks`
* `e2fsprogs`: session management
* `systester-cli`: CPU stress tool
