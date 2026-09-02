# libpdx-volume — CHANGELOG

## 1.1.0 — 2026-09-02 (audit-driven follow-up: issues #16..#31)

**Additive minor release** closing the 16-ticket Phase-2 AISSUE audit
loop against v1.0.0. Every v1.0.0 API surface is preserved
byte-for-byte; new modules and new public symbols are additive only.
Downstream consumers built against v1.0.0 continue to compile and
behave identically.

Six milestones lined up under the LV.M1..LV.M6 axis
(design/tooling/volume-tooling-ux.md §9.4 addendum + the M6
mount-ordering scope):

- **LV.M1 polish (#16..#20)** — surface completeness. `pdxb_verify_
  superblock` scaffolded (fail-closed stub, matches `pdxb_verify_
  inode_tail`); `pdxb_superblock_checksum` + `pdxb_verify_checksum`
  (CRC32C over the [0, 696) signed range, table-driven); complete
  field-accessor family across `PdxbSuperblockSummary` (22 getters +
  10 setters), `MountTableRow` (7 getters), and `MountTableEntry`
  (5 getters); banded `LPV_E_*` error namespace + `lpv_strerror`
  scaffold; `PDXB_ONDISK_BYTES` and `MTE_BYTES` public aliases so
  every documented size constant is reachable by its issue-brief name.
- **LV.M2 hardening (#21..#24)** — surface hardening around the
  release/audit/elevate boundary. Dual-sign + mirror-push run remains
  deferred (external key custody + mirror endpoint). Audit-tracing
  hook (`pdxb_sign_superblock_traced`) landed with `audit_client_slot
  == 0` fast-path fully working; audit-on branch STUB until
  libpdx-audit link-resolvable. `vol_kind_mint_elevate` 3-arg
  signature landed; body STUB until kernel-side mint syscall lands.
  Downstream-consumer smoke witness (`tests/smoke/consumer_e2e.sh`)
  scaffolded; SKIP-gates cleanly when consumer tools are missing.
- **LV.M3 snapshots (#25..#26)** — new `src/vol_snapshot.pdx` module.
  `KIND_VOLUME_SNAPSHOT = 0x1A1` typed. `vol_snapshot_narrow` real
  body (validate + passthrough); `vol_snapshot_mint` / `pdxb_snap_
  create` / `snap_chain_walk` fail-closed stubs. `snap_record_parse`
  real body decoding the 96-byte on-disk snap-metadata record.
- **LV.M4 quotas (#27..#28)** — new `src/pdxb_quota.pdx` module.
  Wire format (superblock quota anchor + 64-byte per-subject row +
  `PDXB_FLAG_HAS_QUOTA` bit); `pdxb_quota_row_parse` /
  `pdxb_quota_row_encode` / `pdxb_quota_table_lookup` real bodies;
  `pdxb_quota_check` covering all four (SOFT / SOFT_GRACE / HARD / OK)
  return codes; `pdxb_quota_commit` with underflow clamp. Inode
  enforcement is scheduled as a v1.1.x follow-up; block path is
  complete.
- **LV.M5 encryption (#29..#30)** — new `src/pdxb_crypto.pdx` module.
  `KIND_KEK = 0x1A2` typed. `pdxb_kek_derive` real body over the
  paideia-as Argon2id intrinsic (RFC 9106 recommended profile);
  `pdxb_dek_wrap` / `pdxb_dek_unwrap` real bodies over ChaCha20-
  Poly1305; `pdxb_block_encrypt` / `_decrypt` STUBS pending paired-
  block metadata layout agreement. PDXB v2 wire format: parser now
  accepts version 1 OR 2, encoder writes v2 iff `PDXB_FLAG_ENCRYPTED`;
  `pdxb_sb_get/set_wrapped_dek` / `pdxb_sb_get/set_kdf_salt` /
  `pdxb_sb_is_encrypted` accessors over the new
  `_reserved[+192, +268)` region (all inside the signed range).
- **LV.M6 multivol ordering (#31)** — new `src/mount_deps.pdx` module.
  Wire format for the dep-list block (magic `'PDDP'`, 128-byte
  per-dep entry with mount-before / mount-after / mount-requires
  kinds); `mount_deps_parse` real body; `mount_table_sort_by_deps`
  STUB pending mountall.pdxfs input-shape agreement (returns a
  distinct `LPV_ORDER_ERR_NOT_IMPL` sentinel so callers can tell
  "algorithm pending" from "real cycle detected").

### Added

- `src/pdxb_checksum.pdx` — CRC32C helpers + 256-entry table (#17).
- `src/lpv_errors.pdx` — banded `LPV_E_*` namespace + `lpv_strerror`
  scaffold (#19).
- `src/vol_snapshot.pdx` — KIND_VOLUME_SNAPSHOT client helpers + snap-
  metadata parser (#25, #26).
- `src/pdxb_quota.pdx` — quota wire format + codec + enforcement
  helpers (#27, #28).
- `src/pdxb_crypto.pdx` — Argon2id KDF + ChaCha20-Poly1305 AEAD
  wrappers (#29).
- `src/mount_deps.pdx` — mount-dependency wire format + parser + topo
  sort scaffold (#31).
- `src/pdxb_sign.pdx` — new public entry points `pdxb_verify_
  superblock` (#16) and `pdxb_sign_superblock_traced` (#22).
- `src/pdxb_superblock.pdx` — 22 getters + 10 setters over
  `PdxbSuperblockSummary` (#18); `PDXB_ONDISK_BYTES` /
  `PDXB_VERSION_V2` / `PDXB_FLAG_HAS_QUOTA` / `PDXB_FLAG_ENCRYPTED`
  constants; PDXB v2 wrapped-DEK/salt/nonce accessors (#30); parser
  accepts v1 OR v2.
- `src/mount_table.pdx` — 7 `MountTableRow` field accessors (#18).
- `src/mount_table_snapshot.pdx` — 5 `MountTableEntry` field
  accessors + `MTE_BYTES` alias (#18, #20).
- `src/vol_kind.pdx` — `vol_kind_mint_elevate` 3-arg elevate-aware
  form (#23).
- `tests/smoke/consumer_e2e.sh` — end-to-end mkfs/mount/snapshot
  scaffold script (#24).

### Deferred substrate (v1.1.x)

- **Kernel-side `KIND_VOLUME_SNAPSHOT`** — landing needed in
  paideia-os. Follow-up filed. Client helpers stub with distinct
  `LPV_SNAP_ERR_NOT_IMPLEMENTED` sentinel until then.
- **Kernel-side `KIND_KEK`** — landing needed in paideia-os. Client
  helpers take raw KEK pointers (design/architecture.md §8.2
  precedent); a KIND_KEK-aware wrapper is a future landing.
- **`mldsa65_verify` intrinsic** — same blocker as v1.0.0. Both
  `pdxb_verify_inode_tail` and the new `pdxb_verify_superblock` stay
  fail-closed stubs until it lands on the `MlDsa65` trait.
- **libpdx-audit / libpdx-elevate link-availability** — the two
  audit- and elevate-branch stubs in `pdxb_sign_superblock_traced` +
  `vol_kind_mint_elevate` become real cross-module calls once those
  siblings are in the build tree.
- **Kernel-side ring-3 `KIND_VOLUME` mint syscall** — `vol_kind_
  mint_elevate`'s body stays a stub until landed.
- **`pdxb_block_encrypt` / `_decrypt`** — pending paired-block
  metadata layout agreement across mkfs.pdxfs + mount.pdxfs
  (design/architecture.md §11).
- **`mount_table_sort_by_deps` full Kahn's-algorithm body** —
  pending mountall.pdxfs input-shape agreement.
- **Full `lpv_strerror` dispatch table** — scaffold returns 0
  (unknown code) for every input at this landing; the LPV_E_* and
  message-string bindings above are the load-bearing part of the
  v1.1.0 change, and the dispatch is a straightforward cmp/jne chain
  to fill in once the code set stabilises.
- **Inode-quota enforcement** — `pdxb_quota_check` / `pdxb_quota_
  commit` cover the block path fully; inode enforcement is a
  duplicate of the same shape against `inodes_used` / `inodes_soft`
  / `inodes_hard` slots and is scheduled as a v1.1.x follow-up.
- **Dual-sign + mirror-push run** — same three gates as v1.0.0
  (paideia-as CI, `pkgs.paideia-os` endpoint, release-line key
  custody). No repo-side action possible at v1.1.0.

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
