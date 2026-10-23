#!/usr/bin/env bash
#
# Copy whole filesystems off disks into $TARGET_ROOT, one directory per source
# partition. Each source is mounted via udisks, rsync'd inside a dtach session
# so the transfer survives a dropped terminal, then unmounted again.
#
# usage: cproot.sh [--archive] [-n|--dry-run] [--] DEVICE...

set -eu

err() {
	echo "[0m[31m$@[0m" >&2
}
warn() {
	echo "[0m[34m$@[0m" >&2
}
die() {
	err "$@"
	exit 1
}

exclude() {
	for f in "$@"
		do printf -- '--exclude=%s ' "$f"
	done
}

# fold anything that isn't alphanumeric into a single '_', so the result is
# safe to use as a directory name
sanitize() {
	printf '%s' "$1" | tr -cs '[:alnum:].' '_' | sed -E 's/^_+//; s/_+$//'
}

# the mountpoint of the filesystem a given path lives on
mountpoint_of() {
	findmnt -no TARGET -T "$1"
}

disk_name() {
	# example: "${MODEL}-${ID}-${PARTLABEL}"
	part="$1"
	parent="$(lsblk -no PKNAME "$part" | head -n1)"
	if [ -n "$parent" ]; then disk="/dev/$parent"; else disk="$part"; fi

	name=""
	for field in \
		"$(lsblk -dno MODEL "$disk")" \
		"$(lsblk -dno SERIAL "$disk")" \
		"$(lsblk -no PARTLABEL "$part" | head -n1)"
	do
		field="$(sanitize "$field")"
		[ -n "$field" ] || continue
		name="${name:+$name-}$field"
	done

	# nothing identifying in sysfs (loop/md/mapper): fall back to the node name
	printf '%s' "${name:-$(basename "$part")}"
}

mount_disk() {
	dev="$1"
	mnt="$(findmnt -nfo TARGET --source "$dev" || true)"
	if test "$mnt"; then
		echo $mnt
		return
	fi

	udisksctl mount --no-user-interaction -b "$dev" >/dev/null || die "failed to mount $dev"
	MOUNTED="$dev"

	mnt="$(findmnt -nfo TARGET --source "$dev" || true)"
	[ -n "$mnt" ] || die "mounted $dev but could not find its mountpoint"
	echo "$mnt"
}

cleanup() {
	[ -n "${MOUNTED:-}" ] || return 0
	dev="$MOUNTED"
	MOUNTED=""
	udisksctl unmount --no-user-interaction -b "$dev" >/dev/null \
		|| warn "failed to unmount $dev"
}

_cproot() {
	[ -b "$1" ] || die "$1 is not a block device"

	SOURCE="$(mount_disk "$1")"

	if test -v ARCHIVE
	then DEST="$TARGET_ROOT/archive/$(disk_name "$1")"
	else DEST="$TARGET_ROOT"
	fi

	EXCLUDE="$(exclude /proc/ /sys/ /dev/ /run/ /swapfile /var/cache/)"

	[ "$(mountpoint_of "$TARGET_ROOT")" != "$SOURCE" ] || die "$TARGET_ROOT is on $1 itself"

	mkdir -p "$DEST"
	set -x #FIXME: this doesn't do what I thought it does
	rsync -aHAX --one-file-system --partial --sparse --progress \
		$EXTRA_RSYNC_OPTS $EXCLUDE "$SOURCE/" "$DEST/"
	set +x

	cleanup
}

TARGET_ROOT="/mnt/gentoo"
EXTRA_RSYNC_OPTS=""
ARCHIVE=

if test "$1" = "--dtach"; then
	shift
	set -eu
	exec dtach -A "/tmp/rsync-$(basename "${@: -1}").dtach" $0 $@
fi


while [ $# -gt 0 ]; do
	case "$1" in
		--root)
			shift
			set -u
			TARGET_ROOT="$1"
			set +u
			shift
			;;
		--dtach)
			die "--dtach must be the first argument or it will not work as you expect"
			;;
		--archive)
			ARCHIVE=y
			shift
			;;
		--throttle)
			# Vital if you're copying an active root_fs from a crappy USB stick
			EXTRA_RSYNC_OPTS="$EXTRA_RSYNC_OPTS --bwlimit=1M"
			shift
			;;
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

[ $# -gt 0 ] || die "usage: $0 [--archive] [-n|--dry-run] [--] DEVICE..."

trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT TERM

[ "$(mountpoint_of "$TARGET_ROOT")" != "$(mountpoint_of /)" ] \
	|| die "$TARGET_ROOT is on the root filesystem, mount the destination disk there first"

for f in "$@"; do
	_cproot "$f"
done
