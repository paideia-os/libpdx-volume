# libpdx-volume — CHANGELOG

## 1.0.0 — 2026-08-31 (R53 wave close, M5-001)

**First release.** Manifest scaffolded for a future dual-signed
(Ed25519 + ML-DSA-65) release per
`design/02-development-environment.md` §1140 (paideia-os); the actual
dual-sign + mirror-push run is deferred (see "Known deferred
substrate" below). Ships `.pdxdoc` for `doc libpdx-volume` and a
release manifest source form targeting
`https://pkgs.paideia-os/main/libpdx-volume/1.0.0/` per
`release/RELEASE-1.0.0.md`.

### Landed

- **M1-001** scaffold + module boundary: three source files
  (`src/vol_kind.pdx`, `src/pdxb_superblock.pdx`,
  `src/mount_table.pdx`), `caps.decl`, `design/architecture.md`. Every
  M1 stub returns a documented sentinel or zeroed struct; none
  dereferences its arguments or issues a syscall.
- **M1-002** `KIND_PDXFS_MOUNT_TABLE` row-layout parser
  (`MountTable::mount_table_row_parse`) — the one M1 function with a
  genuine (non-stub) body, decoding the real 64-byte singleton row
  layout frozen at R53-PREP-001.
- **M2-001** `pdxb_parse_superblock` — every field of the on-disk PDXB
  v1 superblock decoded into a 176-byte `PdxbSuperblockSummary`, four
  validation gates (`buf_len`, `magic`, `version`, `block_size`).
- **M2-002** `pdxb_encode_superblock` — the real inverse: zero-fills
  the 4096-byte output then stamps every field back at its offset.
- **M2-003** `mount_table_snapshot` — walks the live, frozen
  `_mount_table[8]` per-slot array (R16-M1-005) the singleton row's
  `table_row_addr` points at.
- **M2-004** `vol_kind_narrow` — validates `requested_ops_mask` against
  `KIND_VOLUME`'s real op catalog (bits 0..9,
  `VK_OPS_VALID_MASK = 0x3FF`) and passes `cap_slot` through unchanged
  on a valid mask; documented validation + passthrough, not a
  kernel-enforced derivation (no `cap_narrow` primitive exists for
  `KIND_VOLUME`).
- **M3-001** `pdxb_sign_superblock` — real ML-DSA-65 signing via the
  paideia-as `MlDsa65::sign` intrinsic, the first real (non-test)
  caller of that intrinsic found anywhere in the paideia-os /
  paideia-as tree at landing time. Signs `sb_ptr[0, 696)` and writes
  the 3309-byte result to a caller-chosen `out_sig_ptr`.
- **M3-002** `pdxb_sign_inode_tail` (real, same signing path over an
  arbitrary inode-tail byte range; deferred consumer) and
  `pdxb_verify_inode_tail` (documented fail-closed STUB — no
  `mldsa65_verify` intrinsic exists in paideia-as v0.24.0).
- **M4-001** parse-encode round-trip fuzz driver
  (`tests/test_pdxb_roundtrip.pdx`), 100000 iterations against
  `pdxb_parse_superblock` / `pdxb_encode_superblock` via a 64-bit LCG.
- **M4-002** sig-verify fixture driver
  (`tests/test_pdxb_sigverify.pdx`) — asserts
  `pdxb_verify_inode_tail`'s fail-closed sentinel comes back verbatim
  against a deterministic zero-signature fixture; NOT a real
  sign-then-verify round trip (blocked on the same missing verify
  intrinsic M3-002 documents).
- **M4-003** `mount_table_snapshot` correctness matrix
  (`tests/test_mount_table_snapshot.pdx`) — synthetic singleton row +
  8-slot mount-table image, driven through slot counts 0, 1, 7, 8.
- **M5-001** dual-signed release scaffold + `.pdxdoc` + mirror-push
  runbook. Ships `doc/libpdx-volume.pdxdoc` source form,
  `release/manifest.pdxsig.txt` release-manifest source (every hash
  and signature slot a documented placeholder), and
  `release/RELEASE-1.0.0.md` operator runbook + release note. Actual
  dual-sign + mirror-push deferred — see "Known deferred substrate"
  below.

### Known deferred substrate

- **`vol_kind_mint`.** No ring-3-reachable `KIND_VOLUME` mint syscall
  exists yet; the function is a permanent stub until one lands.
- **`vol_kind_narrow`'s kernel-enforced derivation.** No generic
  `cap_narrow` primitive exists anywhere in the kernel tree for
  `KIND_VOLUME`; today's body validates and passes the capability
  through unchanged.
- **`mldsa65_verify` intrinsic.** `pdxb_verify_inode_tail` stays a
  fail-closed stub, and M4-002 stays a sentinel-only test, until this
  lands on the `MlDsa65` trait.
- **Dual-sign + mirror-push run.** Repo-side scaffolding at M5-001 is
  complete. The signed build + HTTP-PUT to
  `pkgs.paideia-os/main/libpdx-volume/1.0.0/` requires: (a) the
  paideia-as ≥ 0.24.0-mldsa65-sign toolchain reachable in CI, (b) the
  `pkgs.paideia-os` mirror endpoint standing (does not exist as of
  R53 close), and (c) a live release-line ML-DSA-65 seed key
  (hardware-backed custody, never repo-resident). Until all three go
  green, `release/manifest.pdxsig.txt` ships with the placeholder
  value `SIGNATURE_PLACEHOLDER_PENDING_LIVE_SIGN` in every signature
  slot; see `design/architecture.md` §10 and `release/RELEASE-1.0.0.md`
  §3.
- **`doc` M2 compile pass.** The `.pdxdoc` compiled binary form ships
  once `doc`.M2 lands. Until then consumers render the source form
  verbatim.
- **Per-mount-entry record (`volume-tooling-ux.md` §2.2 sketch).** No
  kernel representation exists distinct from the singleton
  capability-metadata row and the live `_mount_table[]` vnode-layer
  array this library actually decodes; a future landing may need a
  second entry point rather than a signature change to the existing
  functions.

### Semver policy

- **Major** — wire-format grow past the documented byte layouts,
  error-code renumber, or any API-surface removal.
- **Minor** — additive API surface (e.g. a real `vol_kind_mint` body,
  a real `mldsa65_verify`-backed `pdxb_verify_inode_tail`, a
  kernel-enforced `vol_kind_narrow` derivation).
- **Patch** — correctness fixes, constant tuning, the deferred
  dual-sign + mirror-push run itself (no repo-side code change).
