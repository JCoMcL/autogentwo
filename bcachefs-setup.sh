#!/bin/bash
#
# BCacheFS setup for planD: tiered, 2-way replicated, 8 HDD + 2 NVMe.
#
# Run as root. DESTRUCTIVE: every disk named here is overwritten.
#
# Device inventory this was written against:
#   sda   2.7T Hitachi  XFS sda2          -> data to migrate, then hdd.7
#   sdb   2.7T Hitachi  bare              -> hdd.1
#   sdc   2.7T Hitachi  bare              -> hdd.2
#   sdd   2.7T Hitachi  bcachefs 0.11     -> stale, checksums were "none"
#   sde   2.7T Hitachi  bare              -> hdd.3
#   sdf   2.7T Hitachi  bare              -> hdd.4
#   sdg   2.7T Hitachi  bare              -> hdd.5
#   sdh   2.7T Hitachi  bare              -> hdd.6
#   nvme0n1 745G Intel  XFS p2            -> data to migrate, then nvme.0
#   nvme1n1 745G Intel  NTFS (Windows)    -> verified disposable, nvme.1
#
# Rationale for the non-obvious options is inline below.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Phase 0 - confirm the compression level syntax before touching a real disk
# ---------------------------------------------------------------------------
# bcachefs-tools 1.37.4 documents --compression/--background_compression
# without listing valid values, so the exact level spelling could not be
# confirmed without running it. Format a throwaway image first: if the token
# is wrong this aborts here, while every disk is still intact. Delete this
# phase once you've verified it once.
trap 'rm -f /tmp/bcfs-preflight.img' EXIT
truncate -s 512M /tmp/bcfs-preflight.img
bcachefs format --replicas=2 \
  --compression=zstd-3 \
  --background_compression=zstd-9 \
  /tmp/bcfs-preflight.img
rm -f /tmp/bcfs-preflight.img
trap - EXIT

# ---------------------------------------------------------------------------
# Phase 1 - format the disks that are already clear
# ---------------------------------------------------------------------------
# 6 bare HDDs + the wiped Windows NVMe. ~8.1 TiB usable, which is enough to
# stage the ~2.5 TiB worst case coming off sda and nvme0n1 with room spare,
# so the migration is a single copy rather than a copy-then-recopy.
#
# --replicas=2
#   Sets data and metadata replicas to 2. Survives any two HDD failures, and
#   with metadata at 2 the journal and btrees survive losing the devices that
#   hold them. ~10.9 TiB usable once all 8 HDDs are in (4 pairs' worth).
#
# --foreground_target / --background_target / --promote_target
#   Foreground writes land on NVMe for latency; the rebalance thread migrates
#   cold data to the HDDs; extents read more than once get promoted back to
#   NVMe. These are best-effort - a full target falls back to any device with
#   space. Dot-delimited labels are what let "nvme"/"hdd" resolve to whole
#   groups of devices.
#
# NO --durability=0 (default durability=1 is used instead):
#   durability=0 would make NVMe copies count as nothing toward the replica
#   target, forcing 2 HDD writes per byte. With the default, a foreground
#   write is NVMe + 1 HDD - half the HDD write volume - and the NVMes also
#   contribute to the replica budget, worth roughly 7% more usable capacity.
#   The accepted cost is degraded-not-lost if an SSD dies: bcachefs reports
#   the degraded state and re-replicates. Revisit only if a non-power-loss-
#   protected SSD is ever put in the cache tier, where durability=1 would
#   risk a silently corrupt "replica" rather than an absent one.
#
# --compression=zstd-3
#   Foreground compression runs INLINE in the submitting thread, so per-core
#   speed is what gates a write stream - aggregate cores are irrelevant. This
#   CPU is a Dell PowerEdge T420 class part with AVX but no AVX2, so zstd falls
#   back to its SSE2 path: ~190-250 MB/s per core at level 3. That roughly
#   matches what eight 7200rpm drives can absorb, so level 3 is the ceiling.
#
# --background_compression=zstd-9
#   The opposite trade. Background moves are parallelised across rebalance
#   threads and block nobody, so level 9 (~55-75 MB/s/core) is affordable and
#   gets cold archive data onto the HDDs at a much better ratio. Decompression
#   is ~1 GB/s/core and essentially level-independent, so reads and migration
#   stay I/O-bound rather than CPU-bound.
#
# --encoded_extent_max=128k
#   Raised from the 64k default for better compression ratio on large
#   archived files. Tunable later with `bcachefs set-fs-option`, no reformat
#   needed, and reconcile applies it to existing data in the background.
#
# --metadata_checksum / --data_checksum=crc32c
#   Never "none" again - that is the mistake baked into the old filesystem on
#   sdd, which has no data integrity checking at all. SSE4.2 gives a hardware
#   crc32 instruction, so crc32c costs multiple GB/s per core and is free.
#   xxhash offers nothing here.
#
# --errors=fix_safe
#   On twelve-year-old drives, take safe automatic repairs rather than
#   limping along or panicking.
#
# --write_error_timeout=10
#   Eject a device after 10 consecutive write errors. Favours quickly
#   removing a dying disk over tolerating transient controller resets; tune
#   upward via `set-fs-option` if it proves too eager.
#
# --gc_reserve_percent=10
#   Copygc needs slack to work in. The 8% default is optimistic when free
#   space lives on spinning rust.
#
# --rotation on the HDDs
#   Marks them rotational so reconcile does not treat them as fast devices
#   and hammer them with recovery I/O.
#
# Deliberately NOT used:
#   --nocow          silently disables checksums, compression and encryption
#   --erasure_code   the tools themselves print "DO NOT USE YET"
#   --metadata_target redundant; metadata already follows the foreground
#
bcachefs format \
  --label=hdd.1 /dev/sdb --rotational \
  --label=hdd.2 /dev/sdc --rotational \
  --label=hdd.3 /dev/sde --rotational \
  --label=hdd.4 /dev/sdf --rotational \
  --label=hdd.5 /dev/sdg --rotational \
  --label=hdd.6 /dev/sdh --rotational \
  --label=nvme.1 /dev/nvme1n1 \
  --replicas=2 \
  --foreground_target=nvme \
  --background_target=hdd \
  --promote_target=nvme \
  --compression=zstd-3 \
  --background_compression=zstd-9 \
  --encoded_extent_max=128k \
  --metadata_checksum=crc32c \
  --data_checksum=crc32c \
  --errors=fix_safe \
  --write_error_timeout=10 \
  --gc_reserve_percent=10 \
  -L planD-data

# ---------------------------------------------------------------------------
# Verify the format took, then mount and sanity-check
# ---------------------------------------------------------------------------
# The bracketed alternatives in show-super output are the rejected values, so
# the first value on each line is what is actually in force. If zstd-3,
# zstd-9, 128k or crc32c are not reported here, fix it now - do not migrate
# data onto a filesystem that ignored the options.
bcachefs show-super /dev/sdb | grep -iE \
  'replicas|compression|checksum|encoded_extent'

UUID=$(bcachefs show-super /dev/sdb | awk '/^External UUID:/ {print $3}')
echo "filesystem UUID: $UUID"
# Record this for /etc/fstab:
#   UUID=$UUID  /data  bcachefs  defaults  0  0
# Before it mounts at boot, bcachefs must be in /etc/conf.d/modules so the
# module is loaded ahead of localmount, and fsck.bcachefs wired into `fsck`.

mkdir -p /mnt/bcfs-test
mount -t bcachefs "UUID=$UUID" /mnt/bcfs-test
bcachefs fs usage -h /mnt/bcfs-test

# ===========================================================================
# STOP. Migrate the contents of sda (XFS) and nvme0n1 (XFS) into the mounted
# filesystem, and inspect sdd (stale bcachefs) if you want anything from it.
#
# Mount those two read-only while copying, and mount sdd READ-ONLY too - a
# read-write mount would silently upgrade its 0.11 on-disk format.
#
# Only continue once the copies are verified and you no longer need the
# originals. The next phase erases them.
# ===========================================================================
read -r -p "Type 'migrated' to erase sda, sdd and nvme0n1 and add them: " reply
[ "$reply" = "migrated" ] || { echo "aborted; nothing erased"; exit 1; }

# ---------------------------------------------------------------------------
# Phase 2 - wipe the migrated disks and add them to the filesystem
# ---------------------------------------------------------------------------
# wipefs -a is required, not just for the filesystems but for the partition
# tables: `device add` refuses a disk that still has one, and sda has sda1
# and sda2. -f is needed on sda and sdd because they carry signatures.
#
# sda and sdd join as HDDs; nvme0n1 joins the cache tier. Replica placement
# rebalances across all ten devices on its own, so the pairings do not need
# to match the old layout.
wipefs -a /dev/sda /dev/sdd /dev/nvme0n1

bcachefs device add -f --label=hdd.7  --rotational /dev/sda
bcachefs device add -f --label=hdd.8  --rotational /dev/sdd
bcachefs device add    --label=nvme.0               /dev/nvme0n1

# Adding devices kicks off a background rebalance. Wait for it: the array is
# not properly balanced until it completes, and interrupting it leaves work
# half done.
bcachefs reconcile wait /mnt/bcfs-test

bcachefs reconcile status /mnt/bcfs-test
bcachefs fs usage -h /mnt/bcfs-test
