#!/usr/bin/env sh
# Like `genfstab -U`, but with multi-device bcachefs support.
#
# genfstab resolves each mount's source through blkid. For a multi-device
# bcachefs filesystem the source is a colon-separated device list, which blkid
# cannot resolve, so genfstab falls back to writing that list into fstab.
# Replace it with the filesystem UUID shared by every member, which mount(8)
# and mount.bcachefs both understand.
set -eu

if [ "$#" -ne 1 ]; then
	echo "usage: ${0##*/} MOUNTPOINT" >&2
	exit 2
fi

mp=$1
dir=$(dirname "$0")

uuid=$("$dir/fs-uuid.sh" "$mp" 2>/dev/null || true)

genfstab -U "$mp" | awk -v uuid="$uuid" '
	uuid == "" { print; next }
	$1 == "#" && $2 ~ /:/ {
		sub(/^#[[:space:]]+[^[:space:]]+/, "# UUID=" uuid)
		print
		next
	}
	$3 == "bcachefs" && $1 ~ /:/ {
		sub(/^[^[:space:]]+/, "UUID=" uuid)
	}
	{ print }
'
