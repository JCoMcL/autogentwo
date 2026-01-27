#!/usr/bin/env sh
set -e

error() {
	echo [0m[31m$@[0m >&2
}

warn() {
	echo [1m[34m"$@"[0m >&2
}

die() {
	error $@
	exit 1
}

get_partition() {
	label="$1"
	lsblk -nr -o PATH,PARTLABEL "$DISK" |
		awk -v l="$label" '$2 == l { print $1; exit }'
}

delay() {
	echo [1mproceeding with format in:
	seq 8 -1 1 | while read n; do echo -n "$n "; sleep 1; done
	echo [0m
}

bytes() {
	numfmt --from=iec "$1"
}

sectors() {
	SECTOR_SIZE=$(blockdev --getss "$DISK")
	local b
	b=$(bytes "$1")
	echo $(( (b + SECTOR_SIZE - 1) / SECTOR_SIZE ))
}

assert_valid_size() {
	test 0 -lt "`bytes $1`" || die "invalid size: $1"
}

memory_size() {
	free -b | awk 'NR==2 {print $2}'
}

FILESYSTEM=bcachefs
ESP_SIZE=240M
SWAP=
while [ $# -gt 0 ]; do
	case "$1" in
		-h|--headless)
			delay(){ :; }
			DISK_SELECT_ARGS="$1"
			shift
			;;
		-b|--boot-size)
			shift
			set -u; ESP_SIZE=$1; set +u
			assert_valid_size $ESP_SIZE
			shift
			;;
		-n|--no-boot)
			ESP_SIZE=
			shift
			;;
		-f|--filesystem)
			shift
			set -u; FILESYSTEM=$1; set +u
			command -v mkfs.$FILESYSTEM >/dev/null || die "can't support filesystem: $FILESYSTEM"
			shift
			;;
		-s|--swap-size)
			shift
			set -u; SWAP=$1; set +u
			assert_valid_size $SWAP
			shift
			;;
		-a|--autoswap)
			SWAP=`memory_size`
			assert_valid_size $SWAP
			shift
			;;
		--)
			shift
			break
			;;
		-*|--*)
			die "unrecognized option: $1"
			;;
		*)
			break
			;;
	esac
done

if test "$FILESYSTEM" = bcachefs && ! test `bytes "${SWAP:-0}"` -ge `memory_size`; then
warn "Note: $FILESYSTEM doesn't support swapfiles"
echo "Consider running with [1m'--swap-size `memory_size`'[0m or [1m'--autoswap'[0m for a swap partition large enough to support hibernation with the current memory size
or use the  option"
fi

USER_DISK="${1:-$(disk-select.sh $DISK_SELECT_ARGS)}"
DISK=$(readlink -f "$USER_DISK") || die "Could not find disk: $USER_DISK"
test -b "$DISK" || die "$DISK not a block device"

#I don't suppose any of you guys know a way to do ansi escape codes that isn't annoying to read and to write
echo [1mselected disk is [0m[34m[1m$DISK[0m[1m$(readlink "$DISK">/dev/null && echo , a.k.a. [0m[34m[1m$(readlink -e $DISK))[0m
delay

lsblk -nr -o PATH,MOUNTPOINTS "$DISK" |
while read dev mps; do
	[ -z "$mps" ] && continue

	for mp in $mps; do
		case "$mp" in
			/|/boot|/efi|/usr|/var|/home)
				die "Refusing to unmount critical mountpoint: $mp"
				;;
		esac

		warn "Unmounting $mp"
		umount "$mp"
	done
done

TOTAL_SECTORS=$(sectors $(blockdev --getsize64 "$DISK"))
ESP_SECTORS=${ESP_SIZE:+$(sectors $ESP_SIZE)}
SWAP_SECTORS=${SWAP:+$(sectors $SWAP)}

DISK_LAYOUT="label: gpt
${ESP_SIZE:+"start=, size=$ESP_SECTORS, type=U, name=boot"}
start=, size=${SWAP:+$((TOTAL_SECTORS - ESP_SECTORS - SWAP_SECTORS))}, type=L, name=root
${SWAP:+"start=, size=+, type=S, name=swap"}
"

echo "$DISK_LAYOUT" | sfdisk -walways -Walways "$DISK"

# Wait for changes to take effect
partprobe "$DISK"
udevadm settle

# TODO If using an SSD, should check for firmware upgrades
mkfs.$FILESYSTEM "`get_partition root`"
mkdir -p /mnt/gentoo
mount "`get_partition root`" /mnt/gentoo

if test -n "$ESP_SIZE"; then
	pt="`get_partition boot`"
	mkfs.vfat -F 32 "$pt"
	mkdir -p /mnt/gentoo/efi
	mount "$pt" /mnt/gentoo/efi
fi

if test -n "$SWAP"; then
	pt="`get_partition swap`"
	mkswap "$pt"
	warn "Swap created. When ready, run \`[1mswapon $pt\`"
fi

