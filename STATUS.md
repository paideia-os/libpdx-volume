# libpdx-volume — status

**Wave:** R53 (volume tooling — mkfs / mount / umount + shared library)
**Current milestone:** M2 (core parse + encode) — landed
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

### M2 — Core parse + encode (landed)

- [x] **M2-001** (#3) — `pdxb_parse_superblock`: every offset in R52
      §2.1 decoded into `PdxbSuperblockSummary` (`src/pdxb_superblock.pdx`).
      Cross-checked against `src/tools/mkfs-pdxb/main.pdx` (paideia-os)
      byte-for-byte. Four gates: `buf_len >= 4096`, `magic == PDXB_MAGIC`,
      `version == 1`, `block_size == 4096` (no on-disk checksum field
      exists — see design/architecture.md §3.1 for the substitution
      rationale and the flag for main).
- [x] **M2-002** (#4) — `pdxb_encode_superblock`: real inverse of parse
      (`src/pdxb_superblock.pdx`). Zero-fills the entire 4096-byte
      output first (one bounded loop covers `_reserved` + `sig`
      deterministically), then overlays all eighteen real fields.
      Returns `out_len` on success, `PDXB_ENC_ERR_BUF_TOO_SHORT` on a
      too-small buffer.
- [x] **M2-003** (#5) — `mount_table_snapshot`: reads the
      `KIND_PDXFS_MOUNT_TABLE` singleton row's `table_row_addr` and
      walks the REAL, frozen `_mount_table[8]` per-slot layout from
      `src/kernel/core/fs/mount.pdx` (R16-M1-005) — not an invented
      32-byte record; see design/architecture.md §4.3 for why the
      design doc's §2.2 sketch has no landed kernel representation and
      what this function decodes instead. New file
      `src/mount_table_snapshot.pdx`.
- [x] **M2-004** (#6) — `vol_kind_narrow`: validates `requested_ops_mask`
      against `KIND_VOLUME`'s real op catalog (bits 0..9,
      `VK_OPS_VALID_MASK = 0x3FF`) and passes `cap_slot` through
      unchanged on a valid mask (`src/vol_kind.pdx`). No kernel-side
      `cap_narrow` primitive exists for `KIND_VOLUME` (the only "narrow"
      hit anywhere in the kernel tree is `kind_ec_query.pdx`'s unrelated
      notify-bitmap bit-clear) — see design/architecture.md §5.1 for
      the full rationale and the flag for main. Signature grew from
      2 args (M1 stub) to 3 (out-pointer convention).

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

M3 (signing helpers) opens next. `M3-001` (`pdxb_sign_superblock`)
needs the paideia-as `mldsa65_sign` intrinsic, which has landed
upstream per recent paideia-as version bumps — main should confirm it
is callable from this library's build before M3-001 starts. `M3-002`
(inode-tail sig helpers) has no consumer yet (`fsck.pdxfs` is a
deferred tool) and may be worth deferring further.

`M2-004`'s `vol_kind_narrow` landed as validation + passthrough rather
than a real kernel-enforced narrowing (see `design/architecture.md`
§5.1) because `KIND_VOLUME` still has no `mount`/`flush`/`snapshot` ops
and no generic `cap_narrow` primitive exists anywhere in the kernel
tree for this KIND. Main should track whether a future R53 KIND_VOLUME
landing adds either, at which point `vol_kind_narrow`'s passthrough
line (not its signature) needs to become a real call-through.

## Upstream design

`design/tooling/volume-tooling-ux.md` §2.4 + §9.4 and
`design/filesystem/volume-fs-substrate.md` §2.1 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo carry the
wave-level rationale and the full milestone breakdown. See
[`design/architecture.md`](design/architecture.md) in this repo for the
internal shape.
