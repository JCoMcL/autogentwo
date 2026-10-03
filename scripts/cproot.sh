#!/usr/bin/env sh

err() {
	echo "[0m[31m$@[0m" >&2
}
warn() {
	echo "[0m[34m$@[0m" >&2
}
die() {
	err $@
	exit 1
}

exclude() {
	for f in $@
		do echo -n "--exclude='$f' "
	done
}

disk_name() {
	# example: "${MODEL}-${ID}-${PARTLABEL}"
	basename "$1" #TODO
}

mount_disk() {
	# TODO Assert not already mounted
	sudo udisksctl mount -b /dev/nvme0n1p2 | sed -E 's/Mounted .+? at //'
}

_cproot() {
	SOURCE=$"(mount_disk "$1")"
	DEST="$TARGET/$(disk_name $1)"
	EXCLUDE="$(exclude /proc/ /sys/ /dev/ /swapfile)"
	set -x
	dtach -A rsync.dtach \
	rsync -aHAX --partial --sparse --progress $EXTRA_RSYNC_OPTS $EXCLUDE ${1} ${TARGET}
	set +x
}

TARGET="/mnt/gentoo"
EXTRA_RSYNC_OPTS

while [ $# -gt 0 ]; do
	case "$1" in
		--archive)
			TARGET="/mnt/gentoo/archive"
			shift
		-n|--dry-run)
			EXTRA_RSYNC_OPTS="$EXTRA_RSYNC_OPTS $1"
			shift
			;;
		--)
			shift
			break
			;;
		*)
			break
			;;
	esac
done

set -eu

#TODO: assert $TARGET is on another filesystem
mkdir -p "$TARGET"

for f in "$@"; do
	_cproot "$f"
done
