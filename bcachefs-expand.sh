#!/bin/bash
#
# Add sda, sdd and nvme0n1 to the planD pool.  Run as root.  DESTRUCTIVE.
#
# This is stage 2 of 2.  Do not run it until everything on sda2, nvme0n1p2 and
# sdd is copied into the pool and you have checked the copies.  This script
# erases all three.
#
# It is a separate script from bcachefs-setup.sh rather than a second half of
# it because the gap between the two stages is days, and because the rebalance
# at the end runs for hours - run that part under tmux.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# The disks, by-id
# ---------------------------------------------------------------------------
# Same reasoning as bcachefs-setup.sh: /dev/sdX and /dev/nvmeXn1 move around,
# and getting the two NVMes the wrong way round here wipes the one with your
# data on it.  Check the kernel names in the comments against lsblk; they are
# a reading aid, not a guarantee.

HDD_SDA=/dev/disk/by-id/wwn-0x5000cca058296034   # sda, had XFS on sda2
HDD_SDD=/dev/disk/by-id/wwn-0x5000cca058297d98   # sdd, had bcachefs 0.11

# nvme0n1, serial CVCQ546600JS800EGN - the one that had XFS on p2.
# Whole disk: the ESP lives on the other NVMe, so this one needs no partitions.
NVME_DATA=/dev/disk/by-id/nvme-INTEL_SSDPEDMW800G4_CVCQ546600JS800EGN

MNT=/mnt/planD

mountpoint -q "$MNT" || { echo "$MNT is not mounted"; exit 1; }

# ---------------------------------------------------------------------------
# Show what is about to die
# ---------------------------------------------------------------------------

echo "These will be ERASED:"
for dev in "$HDD_SDA" "$HDD_SDD" "$NVME_DATA"; do
	echo
	echo "  $dev"
	echo "  -> $(readlink -f "$dev")  $(lsblk -dno SIZE,MODEL "$dev")"
	wipefs -n "$dev" | sed 's/^/     /'
done

echo
echo "Current pool:"
bcachefs fs usage -h "$MNT" | head -20
echo

read -r -p "Type 'migrated' to erase those three and add them: " reply
[ "$reply" = migrated ] || { echo "aborted; nothing erased"; exit 1; }

# ---------------------------------------------------------------------------
# Wipe
# ---------------------------------------------------------------------------
# sda has sda1 and sda2, nvme0n1 has p1 and p2, and sdd has an old bcachefs
# superblock.  As in bcachefs-setup.sh: zap both GPTs, clear every remaining
# signature, then make the kernel drop the stale partition nodes.  Leaving the
# backup GPT behind is the one that bites - bcachefs format does not clear it.

for dev in "$HDD_SDA" "$HDD_SDD" "$NVME_DATA"; do
	sgdisk --zap-all "$dev"
	wipefs -af "$dev"
	partprobe "$dev"
done
udevadm settle

# ---------------------------------------------------------------------------
# Add
# ---------------------------------------------------------------------------
# The argument order is `bcachefs device add [options] <filesystem> <device>` -
# the mountpoint comes first and is not optional.
#
# sda and sdd join the HDD group, nvme0n1 joins the cache tier.  Replica
# placement rebalances across all ten devices on its own, so the pairings do
# not have to match the old layout.  As in setup, no --rotational: bcachefs
# reads it out of sysfs.

bcachefs device add --label=hdd.7  "$MNT" "$HDD_SDA"
bcachefs device add --label=hdd.8  "$MNT" "$HDD_SDD"
bcachefs device add --label=nvme.0 "$MNT" "$NVME_DATA"

bcachefs show-super "$HDD_SDA" | grep -E 'Device [0-9]+:|^  Label:|^  Rotational:'

# ---------------------------------------------------------------------------
# Wait for the rebalance
# ---------------------------------------------------------------------------
# Adding devices kicks off a background rebalance.  The array is not properly
# balanced until it finishes and it will take hours on 7200rpm drives, so run
# this under tmux.  Interrupting it is not fatal - it picks up where it left
# off on the next mount - but you want to know when it is actually done.

bcachefs reconcile wait "$MNT"
bcachefs reconcile status "$MNT"
bcachefs fs usage -h "$MNT"

echo
echo "All ten devices in.  Worth considering now, all reversible:"
echo "  bcachefs set-fs-option --metadata_target=nvme $MNT"
echo "      puts the btree on SSD.  foreground_target does not cover metadata;"
echo "      metadata_target defaults to none."
echo "  bcachefs set-fs-option --background_compression=zstd:12 $MNT"
echo "      tighter cold-data compression if you end up wanting the space."
echo "  bcachefs scrub $MNT"
echo "      verifies every checksum.  Worth a baseline run on drives this old."
