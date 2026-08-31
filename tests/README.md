# tests/ — libpdx-volume test suite (M4)

**Milestone lineage.** M4 in `design/tooling/volume-tooling-ux.md` §9.4
(paideia-os). Three issues under this milestone in the
`paideia-os/libpdx-volume` repo:

- **#9 — M4-001** parse-encode round-trip fuzz (10^5 random
  `PdxbSuperblockSummary` field values).
- **#10 — M4-002** sig-verify against a known-signed superblock
  fixture.
- **#11 — M4-003** `mount_table_snapshot` correctness matrix (0, 1, 7,
  8 rows).

All three landed at M4.

## Files

- `test_pdxb_roundtrip.pdx` — M4-001 driver. Exports
  `TestPdxbRoundtrip::run() -> u64`. Runs 100000 (10^5) fuzz iterations
  over `pdxb_encode_superblock` / `pdxb_parse_superblock`
  (`src/pdxb_superblock.pdx`, M2), holding the three gate fields
  (magic, version, block_size) at their one legal value each iteration
  and drawing every other `PdxbSuperblockSummary` field from a 64-bit
  LCG (`state = state * 6364136223846793005 + 1442695040888963407 mod
  2^64`). Returns 0 on all-pass, 1 on an encode-step failure, 2 on a
  parse-step failure, or `100 + field_ordinal` (101..122) on the first
  field mismatch. Pure leaf plus two cross-module calls into this
  library's own codec (effects `!{mem} @{}`) — no syscall.
- `test_pdxb_sigverify.pdx` — M4-002 driver. Exports
  `TestPdxbSigverify::run() -> u64`. Builds a deterministic
  "known-blank-superblock + zero-signature-placeholder" fixture in
  `.bss` (magic/version/block_size stamped, everything else — including
  the entire signature region — left at its zero-init value) and calls
  `PdxbSign::pdxb_verify_inode_tail` (`src/pdxb_sign.pdx`, M3-002)
  against it. `pdxb_verify_inode_tail` is a scaffold STUB — no
  `mldsa65_verify` intrinsic exists in paideia-as v0.24.0 — so this
  driver asserts the stub's fail-closed sentinel
  (`PDXB_VER_ERR_NOT_IMPLEMENTED`, `0xFFFFFFFFFFFFFFFF`) comes back
  verbatim rather than performing a real sign-then-verify round trip.
  Returns 0 if the sentinel matched, 1 otherwise. A real M4-002 round
  trip is blocked on a verify intrinsic landing on the `MlDsa65` trait
  (or a sibling trait) — see the file's own header for the full
  rationale.
- `test_mount_table_snapshot.pdx` — M4-003 driver. Exports
  `TestMountTableSnapshot::run() -> u64`. Builds a synthetic
  `KIND_PDXFS_MOUNT_TABLE` row plus a synthetic 8-slot `_mount_table[]`
  image in `.bss` (each slot carrying five distinct, deterministic
  field values so an off-by-one in the walk loop cannot hide behind
  identical data) and drives `MountTableSnapshot::mount_table_snapshot`
  (`src/mount_table_snapshot.pdx`, M2-003) through `mount_slot_count` =
  0, 1, 7, and 8 (full), verifying `out_count` and every decoded entry
  each time. Returns 0 if all four cases passed, or the 1-based ordinal
  (1..4) of the first case that failed.

## Return-code convention

Every M4 test driver in this tree returns a `u64` where `0` means "all
subtests/iterations/cases passed" and any nonzero value identifies
which one failed first (see each file's own header for its exact
nonzero-code table). This mirrors — deliberately, not by coincidence —
[`libpdx-audit`](https://github.com/paideia-os/libpdx-audit)'s own M4
test-driver convention, this org's other satellite library, for the
same underlying reason: **libpdx-volume has no console/print
capability anywhere in `caps.decl`**, so a driver cannot literally
`emit "..." ; exit N` the way a runnable CLI tool would. Every issue
brief in this milestone (#9, #10, #11) describes its pass/fail contract
in "emit \<message\>, exit \<code\>" terms; each driver's own header
documents the exact return-code table that stands in for that
literal text, so a future consumer — a runnable test-runner tool that
DOES have a print primitive, per libpdx-audit's own M4-001 QEMU
protocol precedent — can map a nonzero return straight to the message
the issue asked for.

A test harness (in a future consumer tool) walks the driver list and
reports each nonzero return using the table in that driver's own file
header; the process exits 0 iff every driver returned 0.

## Why the drivers do not invoke any syscall

libpdx-volume is a shared library — no runnable executable of its own
(`tools/build.sh` compiles every `src/*.pdx` and `tests/*.pdx` file to
its own `.o` independently, with **no link step** — cross-module calls
like `test_pdxb_roundtrip.pdx`'s `call pdxb_encode_superblock;` are
unresolved-external references in the test file's own object, resolved
only once a future consumer tool links this library's `src/` alongside
these drivers). Every public entry point this library exposes
(`pdxb_parse_superblock`, `pdxb_encode_superblock`,
`mount_table_snapshot`, `pdxb_sign_*`, `pdxb_verify_inode_tail`,
`vol_kind_*`, `mount_table_row_parse`) is itself a pure `.bss`/pointer
leaf with **zero cap-invoke or syscall calls anywhere** — the
library's own established discipline, restated at every milestone in
`design/architecture.md`. The three drivers here inherit that
discipline for free: none of them needs to fault-inject around a
syscall the way libpdx-audit's drivers do (that library DOES issue
syscalls transitively through `audit_send_record`), because nothing in
libpdx-volume's own call graph ever reaches one.

## What a full QEMU smoke matrix still needs

- **M4-001 / M4-003** are fully self-contained today: both drivers
  exercise real, non-stub bodies (`pdxb_parse_superblock` /
  `pdxb_encode_superblock` / `mount_table_snapshot`) entirely through
  `.bss` and caller-supplied pointers. A future consumer tool
  (`mkfs.pdxfs`, `fsck.pdxfs`, or a small `examples/` binary hosted
  here) linking `src/` alongside these two drivers and printing their
  return codes is the only thing missing before these run under real
  QEMU boot.
- **M4-002** additionally needs a real `mldsa65_verify` intrinsic on
  the `MlDsa65` trait (paideia-as) before a genuine sign-then-verify
  round trip can be written; today's driver only proves the STUB's
  fail-closed contract holds.
