# libpdx-volume — status

**Wave:** R53 (volume tooling — mkfs / mount / umount + shared library)
**Current milestone:** M1 (design + skeleton) — in progress
**Version:** unreleased (pre-1.0.0)

See `design/tooling/volume-tooling-ux.md` §9.4 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo for the
full 12-issue breakdown this checklist mirrors.

## Milestone checklist

### M1 — Design + skeleton

- [x] **M1-001** — scaffold + module boundary (`vol_kind_mint`,
      `vol_kind_narrow`, `pdxb_parse_superblock`,
      `pdxb_encode_superblock` stubs): landed. Three source files
      (`src/vol_kind.pdx`, `src/pdxb_superblock.pdx`,
      `src/mount_table.pdx`), `caps.decl`, `design/architecture.md`.
      Every stub returns a documented sentinel or zeroed struct; none
      dereferences its arguments or issues a syscall.
- [x] **M1-002** — `KIND_PDXFS_MOUNT_TABLE` row-layout parser (matches
      R53-PREP-001): landed. `MountTable::mount_table_row_parse`
      (`src/mount_table.pdx`) decodes the real 64-byte row layout from
      `src/kernel/core/cap/kind_pdxfs_mount_table.pdx` SECTION 1 in the
      paideia-os repo — the only M1 function with a genuine body rather
      than a stub, since that row layout is already frozen kernel-side.
      Returns `LPV_MTR_OK` (0), `LPV_MTR_ERR_BAD_MAGIC` (1), or
      `LPV_MTR_ERR_ROW_DEAD` (2).
- [ ] **M1-003** — (not itemised as a separate issue in
      volume-tooling-ux.md §9.4's libpdx-volume list; §9.4's own table
      only names M1-001/M1-002 for this repo, unlike the three CLI
      tools which each carry an M1-003 "first runnable" issue). Flagged
      for main: confirm libpdx-volume's M1 milestone is complete at
      two issues, or whether a third scaffold-verification issue should
      be opened before M2 begins.

### M2 — Core parse + encode (pending)

- [ ] **M2-001** — `pdxb_parse_superblock`: every offset in R52 §2.1 →
      `PdxbSuperblockSummary`.
- [ ] **M2-002** — `pdxb_encode_superblock`: inverse of parse; canonical
      byte layout.
- [ ] **M2-003** — `mount_table_snapshot`: read `KIND_PDXFS_MOUNT_TABLE`
      + return `Vec<MountTableRow>`.
- [ ] **M2-004** — `vol_kind_narrow`: narrow `ops_mask` on `KIND_VOLUME`
      (matches R52 op catalog).

### M3 — Signing helpers (pending)

- [ ] **M3-001** — `pdxb_sign_superblock` via paideia-as `mldsa65_sign`
      intrinsic.
- [ ] **M3-002** — inode-tail sig helpers (used by future `fsck.pdxfs`;
      deferred consumer).

### M4 — Tests + fuzz (pending)

- [ ] **M4-001** — parse-encode round-trip fuzz (10^5 random superblock
      field values).
- [ ] **M4-002** — sig-verify against a known-signed superblock fixture.
- [ ] **M4-003** — `mount_table_snapshot` correctness matrix (0 rows, 1
      row, 7 rows, full 8 rows).

### M5 — Signed release (pending)

- [ ] **M5-001** — dual-signed release + `.pdxdoc` + mirror push.

## Next milestone

M2 opens once `libpdx-volume.M1` closes and the two substrate-prep
blockers named in `design/tooling/volume-tooling-ux.md` §9.0
(`R53-PREP-000` UEJ constants, `R53-PREP-001`
`KIND_PDXFS_MOUNT_TABLE` — already landed in paideia-os as of this M1
landing) are satisfied. `M2-004` (`vol_kind_narrow`) additionally needs
`KIND_VOLUME`'s op catalog to gain `{mount, flush, snapshot}` ops it
does not have yet (see `design/architecture.md` §5) — main should
confirm whether that gap blocks `M2-004` opening or whether the issue
should be re-scoped.

## Upstream design

`design/tooling/volume-tooling-ux.md` §2.4 + §9.4 and
`design/filesystem/volume-fs-substrate.md` §2.1 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo carry the
wave-level rationale and the full milestone breakdown. See
[`design/architecture.md`](design/architecture.md) in this repo for the
internal shape.
