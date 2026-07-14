#!/bin/bash
#
# Mount partition 1 of a kata guest rootfs image at /mnt/disk and echo the loop
# device on the last stdout line (used by kata-update-guest-image.sh for the
# matching umount). Refuses if the image is already looped.

set -ex

img_file="$1"

img_file_basename=$(basename "$img_file")
dev=$(sudo losetup | grep "$img_file_basename" || true)
if [[ ! -z "$dev" ]]; then
	echo "$img_file_basename was mounted"
	exit 1
fi

sudo mkdir -p /mnt/disk

sudo losetup -f "$img_file"
filename=$(basename "$img_file")
filename="${filename%%.*}"

dev=$(losetup | grep "$filename" | awk '{print $1}')
f=$(basename "$dev")

sudo kpartx -a "$dev"
sudo mount /dev/mapper/${f}p1 /mnt/disk

echo "$dev"
