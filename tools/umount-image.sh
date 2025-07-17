#!/bin/bash

set -x

sudo umount /mnt/disk/
sudo kpartx -d "$1"
sudo losetup -d "$1"
