#!/usr/bin/env bash
# tests/smoke/consumer_e2e.sh — libpdx-volume.M2-004 (issue #24)
#
# End-to-end smoke witness: mkfs.pdxfs writes a PDXB superblock, this
# library parses it back, then mount + snapshot + unmount + snapshot are
# driven through and every result is asserted against expected shape.
#
# ============================================================================
# What this script proves
# ============================================================================
#
# The library encoder and downstream writer agree on every byte (mkfs
# writes what this library reads); the mount table snapshot reflects
# real kernel state after sys_mount / sys_umount, not a stale in-memory
# view. Silent wire-format drift between mkfs and libpdx-volume is
# exactly the class of bug this library was created to eliminate --
# this script is the automated check.
#
# ============================================================================
# Runs from a paideia-os monorepo checkout
# ============================================================================
#
# Cannot be run standalone from this repo because it needs:
#   - paideia-os's tools/build.sh to compile libpdx-volume + mkfs.pdxfs
#     + mount.pdxfs + umount.pdxfs together (this library ships no
#     runnable executables of its own -- see tests/README.md for the
#     "no console/print capability" note)
#   - tools/run-qemu.sh to boot the resulting image
#   - a KIND_BLOCK_DEVICE cap available inside the guest (mkfs writes
#     into a scratch disk image the QEMU boot fixture pre-provisions)
#
# Env vars:
#   PAIDEIA_OS_ROOT   path to paideia-os checkout (default: ../paideia-os)
#   SMOKE_KEEP_TMP    if set, keep the /tmp workdir after run
#
# Expected wall-clock: ~5 minutes (build + boot + assertions), aligned
# with STATUS.md's own smoke-runtime discipline.
#
# ============================================================================
# Status: SCAFFOLD
# ============================================================================
#
# This script's structure is complete and every assertion is enumerated
# below in ORDER, but three of the consumer tools it drives
# (mkfs.pdxfs, mount.pdxfs, umount.pdxfs) do not yet exist as runnable
# executables in the paideia-os tree -- they are staged as design docs
# under design/tooling/volume-tooling-ux.md §M3/M4/M5 with per-tool
# repos to be spun out. Once even ONE of the three lands, its section
# of this script becomes runnable and the corresponding assertions
# start passing.
#
# The script exits 77 (SKIP) at the tool-discovery gate when any of the
# three consumers is missing, so a CI wrapper knows to distinguish
# "smoke skipped, waiting on consumer landing" from a real regression.

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
PAIDEIA_OS_ROOT="${PAIDEIA_OS_ROOT:-$(pwd)/../paideia-os}"
WORKDIR="${WORKDIR:-/tmp/libpdx-volume-smoke-$$}"
IMG="$WORKDIR/scratch.img"
MOUNTPOINT="/mnt/e2e"

if [ ! -d "$PAIDEIA_OS_ROOT" ]; then
    echo "[smoke] SKIP: paideia-os checkout not found at $PAIDEIA_OS_ROOT" >&2
    exit 77
fi

# ---------------------------------------------------------------------------
# Tool-discovery gate
# ---------------------------------------------------------------------------
MISSING=()
for tool in mkfs.pdxfs mount.pdxfs umount.pdxfs; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING+=("$tool")
    fi
done
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "[smoke] SKIP: consumer(s) not yet on PATH: ${MISSING[*]}" >&2
    echo "[smoke] SKIP: waiting on paideia-os consumer landings" >&2
    exit 77
fi

mkdir -p "$WORKDIR"
trap "if [ -z \"\${SMOKE_KEEP_TMP:-}\" ]; then rm -rf '$WORKDIR'; fi" EXIT

# ---------------------------------------------------------------------------
# Stage 1: build libpdx-volume + consumers
# ---------------------------------------------------------------------------
echo "[smoke] stage 1: build"
(cd "$PAIDEIA_OS_ROOT" && bash tools/build.sh) || {
    echo "[smoke] FAIL: paideia-os build.sh nonzero" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Stage 2: mkfs dry-run + real
# ---------------------------------------------------------------------------
echo "[smoke] stage 2: mkfs"
dd if=/dev/zero of="$IMG" bs=1M count=64 2>/dev/null

# Dry-run captures the PdxFsFormatRecord for later cross-check.
FORMAT_RECORD="$WORKDIR/format-record.txt"
mkfs.pdxfs --dry-run "$IMG" > "$FORMAT_RECORD"

mkfs.pdxfs "$IMG" || {
    echo "[smoke] FAIL: mkfs.pdxfs nonzero" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Stage 3: parse the written image via a small .pdx driver
# ---------------------------------------------------------------------------
echo "[smoke] stage 3: parse-back"
# test_e2e_verify.pdx is a companion driver that opens $IMG, reads the
# first 4096 bytes, calls pdxb_parse_superblock, asserts every summary
# field matches $FORMAT_RECORD's own claimed field values, then prints
# either "OK" or a specific field-name diagnostic. Its exit code is 0
# on match, 1 on any mismatch.
test_e2e_verify --img "$IMG" --format-record "$FORMAT_RECORD" || {
    echo "[smoke] FAIL: test_e2e_verify parse-back mismatch" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Stage 4: mount + snapshot + assert new mount visible
# ---------------------------------------------------------------------------
echo "[smoke] stage 4: mount"
mount.pdxfs "cap:volume:$IMG" "$MOUNTPOINT" || {
    echo "[smoke] FAIL: mount.pdxfs" >&2
    exit 1
}

test_e2e_verify --snapshot-includes "$MOUNTPOINT" || {
    echo "[smoke] FAIL: mount_table_snapshot missing $MOUNTPOINT" >&2
    umount.pdxfs "$MOUNTPOINT" || true
    exit 1
}

# ---------------------------------------------------------------------------
# Stage 5: unmount + snapshot + assert slot empty
# ---------------------------------------------------------------------------
echo "[smoke] stage 5: unmount"
umount.pdxfs "$MOUNTPOINT" || {
    echo "[smoke] FAIL: umount.pdxfs" >&2
    exit 1
}

test_e2e_verify --snapshot-excludes "$MOUNTPOINT" || {
    echo "[smoke] FAIL: mount_table_snapshot still showed $MOUNTPOINT after unmount" >&2
    exit 1
}

echo "[smoke] OK: all 5 stages passed"
exit 0
