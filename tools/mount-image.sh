#!/bin/bash

set -ex

img_file="$1"

img_file_basename=$(basename $img_file)
dev=$(sudo losetup | grep $img_file_basename || true)
if [[ ! -z "$dev" ]]; then
	echo "$img_file_basename was mounted"
	exit 1
fi

sudo mkdir -p /mnt/disk

sudo losetup -f $img_file
filename=$(basename $img_file)
filename="${filename%%.*}"

dev=$(losetup | grep $filename | awk '{print $1}')
f=$(basename $dev)

sudo kpartx -a $dev
sudo mount /dev/mapper/${f}p1 /mnt/disk

echo "$dev"
