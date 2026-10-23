#!/usr/bin/env sh
# Print the filesystem UUID of the filesystem mounted at MOUNTPOINT.
#
# Multi-device bcachefs is why this exists: findmnt reports its source as a
# colon-separated list (/dev/sdb:/dev/sdc:...), so `findmnt -o UUID` and
# `genfstab -U` resolve nothing and fall back to device names. Every member
# of a bcachefs filesystem carries the same filesystem UUID, so looking at any
# one member gives the identifier that both root= and /etc/fstab should use.
# There is no single PARTUUID to use instead.
set -eu

if [ "$#" -ne 1 ]; then
	echo "usage: ${0##*/} MOUNTPOINT" >&2
	exit 2
fi

src=$(findmnt -n -o SOURCE --target "$1")
device=${src%%:*}

# udev already knows the UUID and this works without root; blkid is the
# fallback for environments without a udev database.
uuid=$(udevadm info --query=property --name="$device" 2>/dev/null |
	sed -n 's/^ID_FS_UUID=//p' | head -n 1)
if [ -z "$uuid" ]; then
	uuid=$(blkid -s UUID -o value "$device" 2>/dev/null || true)
fi

if [ -z "$uuid" ]; then
	echo "${0##*/}: no filesystem UUID found for $device" >&2
	exit 1
fi

echo "$uuid"
