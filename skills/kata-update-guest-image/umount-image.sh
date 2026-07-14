#!/bin/bash
#
# Unmount /mnt/disk and tear down the loop device created by mount-image.sh.
# Usage: umount-image.sh <loopdev>   (e.g. /dev/loop1)

set -x

sudo umount /mnt/disk/
sudo kpartx -d "$1"
sudo losetup -d "$1"
