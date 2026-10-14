# libpdx-volume — CHANGELOG

## 1.1.10 — 2026-10-13 (PFS-14 / paideia-os#2732: pdxb_block_encrypt / _decrypt real bodies)

**Patch bump — additive and signature-widening (the four-arg stub
retired here was fail-closed, so no caller depended on its shape).
Closes the per-block encrypt-at-rest path PFS-05 froze in design/
pdxfs/block-crypto-contract.md and PFS-13 (Wave 97) prepared via
sys_dek_seal.** Closes `paideia-os#2732` (PFS-14, Wave PFS-W11).

### Added

- **`src/pdxb_crypto.pdx`** — `PdxbCrypto::pdxb_block_encrypt`
  real body (new signature `(buf_ptr, lba) -> u64`). Marshals a
  syscall against sysno 137 (sys_dek_apply, paideia-os-side) with
  mode=0, carrying the cached dek_row_id + volume_prefix from
  mount-time .bss state. The 32-byte DEK never leaves kernel
  space (closes GAP #P2 in mount.pdxfs's passphrase_wire.pdx). The
  caller's buffer is 4112 bytes (4096 data + 16 tag inline);
  PFS-14b will own the on-disk pairing of these frames with their
  persistent metadata block. Returns `LPV_CRYPTO_OK` (0),
  `LPV_CRYPTO_ERR_NO_DEK` (0x0907), `LPV_CRYPTO_ERR_SYSCALL`
  (0x0906), `LPV_CRYPTO_ERR_LBA_EXHAUSTED` (0x0908), or
  `LPV_CRYPTO_ERR_AEAD_FAIL` (0x0903).
- **`src/pdxb_crypto.pdx`** — `PdxbCrypto::pdxb_block_decrypt`
  real body (new signature `(buf_ptr, lba) -> u64`). Mirror of
  the encrypt side with mode=1. The caller provides ciphertext
  + tag in the 4112-byte buffer; the kernel-side AEAD open
  verifies the tag and writes 4096 plaintext bytes back (the tag
  slot at buf+4096 is left untouched). Same return taxonomy.
- **`src/pdxb_crypto.pdx`** — mount-time setters +
  symmetric getters: `pdxb_crypto_set_dek_row_id(row_id)`,
  `pdxb_crypto_set_volume_prefix(prefix_u32)`,
  `pdxb_crypto_get_dek_row_id()`, `pdxb_crypto_get_volume_prefix()`.
  mount.pdxfs's post-sys_dek_seal hook installs the row_id (from
  the seal syscall's `rax >> 2`) and the first 4 bytes of the
  superblock's kdf_salt. _lpv_dek_row_id defaults to the sentinel
  `LPV_DEK_ROW_UNSET` (0xFFFFFFFFFFFFFFFF); the preflight in both
  bodies maps a non-overwritten sentinel to `LPV_CRYPTO_ERR_NO_DEK`
  WITHOUT issuing the syscall.
- **`src/pdxb_crypto.pdx`** — three new return-code constants in
  the already-reserved 0x0900..0x09FF crypto band:
  `LPV_CRYPTO_ERR_SYSCALL = 0x0906` (kernel SDA_INVALID_PAGE /
  SDA_INVALID_MODE), `LPV_CRYPTO_ERR_NO_DEK = 0x0907` (library
  preflight OR kernel SDA_INVALID_ROW), `LPV_CRYPTO_ERR_LBA_EXHAUSTED
  = 0x0908` (kernel SDA_INVALID_LBA, nonce birthday-bound at 2^48
  per PFS-05 §4.2). The dispatch brief named
  `LPV_CRYPTO_ERR_SYSCALL = 0x0902` but 0x0902 was already
  `LPV_CRYPTO_ERR_KDF_FAIL` from v1.1.0 (M5-001); allocating
  0x0906+ preserves the v1.0.x numeric-stability contract
  documented in `src/lpv_errors.pdx` §Compatibility posture.
- **`tests/test_pdxb_block_crypto.pdx`** — new test driver with
  six cases over the library-side logic (NO_DEK preflight,
  happy encrypt, happy decrypt, AEAD fail, LBA exhausted, invalid
  row). Uses the mock-syscall gate `_lpv_crypto_syscall_mock_enable`
  / `_lpv_crypto_syscall_mock_rax` added here so the test runs
  without a live kernel (same shape as `test_vol_kind_mint.pdx`).
  A full plaintext-round-trip + real-AEAD test belongs in a QEMU
  smoke scenario, not a unit driver.

### Retired

- The v1.1.0 four-arg `pdxb_block_encrypt(dek_ptr, block_ptr,
  nonce_ptr, out_tag_ptr)` + `pdxb_block_decrypt(dek_ptr,
  block_ptr, nonce_ptr, tag_ptr)` stubs that returned
  `LPV_CRYPTO_ERR_NOT_IMPL` (0x0901) are retired in favor of the
  two-arg real bodies. No caller depended on the 4-arg stub
  (grep audit at landing time surfaces STATUS.md / CHANGELOG /
  design-doc references only); the 0x0901 return code remains
  in the band for backward-compatibility, no longer emitted.

### Deferred

- **`src/pdxb_block_meta.pdx`** (new module, PFS-14b) — the
  on-disk paired-metadata module per PFS-05 §5: 32-byte records
  (nonce[12] + tag[16] + flags[1] + reserved[3]), 128 records
  per metadata block, tail-of-data-region layout, with
  `pdxb_block_meta_read` / `_write` helpers. Deferred because the
  bodies landed here handle the AEAD transport within a single
  user buffer (data[4096] + tag[16] = 4112 B); persisting that
  tag to a paired block is a separate scope (needs mkfs.pdxfs
  wire-up for `meta_region_lba_start`, atomicity-under-WAL
  design decisions, and the three new superblock accessor pairs
  below). Follow-up ticket to be filed.
- Three new superblock accessor pairs
  (`pdxb_sb_get/set_epoch_counter` at `sb+268`,
  `pdxb_sb_get/set_meta_region_lba_start` at `sb+276`,
  `pdxb_sb_get/set_meta_block_count` at `sb+284`) per PFS-05 §5.3.
  Deferred with PFS-14b.

## 1.1.8 — 2026-10-11 (PFS-08 / paideia-os#2575: inode-path quota check + commit)

**Patch bump — additive. Closes the inode-path half of the quota
subsystem whose block-path pair landed in v1.1.0 (LV.M4 / #28) and
whose module header had carried the "inode enforcement is a
straightforward duplicate of the block path … scheduled as a v1.1.x
follow-up" flag ever since. Two new public symbols, three new
return codes in the already-reserved 0x0800..0x08FF quota band, one
new test driver.** Closes `paideia-os#2575` (PFS-08, chain-head wave
PFS-W5).

### Added

- **`src/pdxb_quota.pdx`** — `PdxbQuota::pdxb_quota_check_inode`
  real body (`(quota_summary_ptr, inode_delta) -> u64`). Mirrors
  the block-path `pdxb_quota_check`'s shape against the inode slots
  of the same 88-byte decoded summary (`PDXQ_OFF_INODES_USED` +64
  reader, `PDXQ_OFF_INODES_HARD` +80 reader) with a deliberately
  simpler, hard-limit-only verdict surface -- no soft/grace path,
  no `grace_expired` parameter. Returns `LPV_QUOTA_OK` (0),
  `LPV_QUOTA_ERR_INODE_OVER` (0x0806) on `new > inodes_hard`,
  `LPV_QUOTA_ERR_INODE_OVERFLOW` (0x0807) on `inodes_used +
  inode_delta` wrapping past 2^64, or `LPV_QUOTA_ERR_BAD_ROW`
  (0x0804, reused) on magic mismatch. `0 = no limit` semantics
  apply to `inodes_hard` the same way as to `blocks_hard` in the
  block path. Overflow guard follows the issue #33 precedent:
  `add r10, rsi; jb lpv_qci_overflow` refuses any raw 2^64 wrap
  before the cmp-vs-hard branch can see a bogus wrapped value.
  Does NOT mutate the summary -- the sibling `_commit_inode` is
  the mutation entry point.
- **`src/pdxb_quota.pdx`** — `PdxbQuota::pdxb_quota_commit_inode`
  real body (`(quota_summary_ptr, inode_delta) -> u64`). Mirrors
  `pdxb_quota_commit` against the inode slot (+64) with explicit
  positive-delta overflow handling: a positive-delta add that
  wraps past 2^64 returns `LPV_QUOTA_ERR_INODE_OVERFLOW` (0x0807)
  without mutating the summary. Negative-delta underflow retains
  the sibling block-path's established clamp-to-zero policy
  (quota drift is recoverable via fsck.pdxfs's future
  recompute-inodes-used pass). Returns `LPV_QUOTA_OK` (0) after a
  successful in-memory store.
- **`src/pdxb_quota.pdx`** — three new return-code constants in
  the already-reserved 0x0800..0x08FF band:
  `LPV_QUOTA_ERR_INODE_OVER = 0x0806`,
  `LPV_QUOTA_ERR_INODE_OVERFLOW = 0x0807`,
  `LPV_QUOTA_ERR_INODE_WRITEBACK = 0x0808`. The first two are
  emitted by the two new helpers. The third is published but
  deliberately not emitted at this landing: both helpers mutate
  only the in-memory summary (same posture as `pdxb_quota_commit`),
  so writeback failures surface at the caller's own
  `pdxb_quota_row_encode` + block-write step. The code is
  reserved so a future wave that wires a real
  superblock-writeback helper through this library can emit it
  without a return-surface breaking change.
- **`tests/test_quota_inode.pdx`** (new file) —
  `TestQuotaInode::test_quota_inode_run()` five-case correctness
  matrix:
  (1) under-quota check (used=10, hard=100, delta=50 -> OK);
  (2) at-boundary check (used=50, hard=100, delta=50 -> OK;
      `ja` strict > discipline means new == hard is at-boundary OK);
  (3) over-quota check (used=50, hard=100, delta=51 ->
      `LPV_QUOTA_ERR_INODE_OVER` 0x0806);
  (4) overflow guard (used=0xFFFFFFFFFFFFFFF0, delta=0x20 ->
      `LPV_QUOTA_ERR_INODE_OVERFLOW` 0x0807 via the
      `add; jb` guard firing before the cmp-vs-hard branch);
  (5) commit idempotence (two consecutive `commit(+5)` accumulate
      to inodes_used == 10, both calls returning
      `LPV_QUOTA_OK`).
  Cases 1/2/3 additionally verify that `_check_inode` does not
  mutate the summary's inodes_used slot. Returns 0 on all-pass or
  the 1-based ordinal of the first failing case per the shared M4
  return-code convention (`tests/README.md`). 88-byte summary
  fixture lives in the driver's own `.bss`; every non-inode slot
  is left at its zero-init value (the inode-path helpers never
  read those slots).

### Changed

- **`src/pdxb_quota.pdx`** — module header gains a new
  "Inode-path helpers (LV.M11 / PFS-08)" section documenting the
  simplified hard-only shape, the two new refusal codes, the
  summary-layout offsets consulted (`PDXQ_OFF_INODES_USED` +64,
  `PDXQ_OFF_INODES_HARD` +80), and the writeback-code reserve
  rationale. "Label prefixes" bullet extended with
  `lpv_qci_` (check_inode) and `lpv_qcmi_` (commit_inode).

### Notes

- Encoder-pitfall discipline: no `test rN,rN`; no `add reg,[mem]`;
  no 2-op `imul reg,imm`; no multiline `pub let =`; no reserved
  labels (`loop`/`if`/`let`; all labels prefixed `lpv_qci_` /
  `lpv_qcmi_` in src and `tqi_` in the test). All status-code
  immediates fit imm32 sign-extend; the one 64-bit immediate
  (0xFFFFFFFFFFFFFFF0 for case 4) stages via MOVABS per
  `test_pdxb_sigverify.pdx`'s precedent. `jb` (jump-if-carry)
  spelling for the overflow guard matches `pdxb_quota_check`'s
  own `lpv_qc_overflow_refuse` discipline (issue #33 precedent).

## 1.1.7 — 2026-10-11 (PFS-07 / paideia-os#2574: real snap_chain_walk body + 4-case correctness matrix)

**Patch bump — the one caller in the paideia-os tree
(`mount.pdxfs/src/snapshot_wire.pdx::snapshot_wire_list`) is
explicitly flagged in `mount.pdxfs/CHANGELOG.md` as "reachable only
once snap_chain_walk gains a real body". That body lands here with
a new 3-arg signature replacing v1.1.0's 5-arg stub, so main must
bump the libpdx-volume submodule in paideia-os AND adapt that one
caller in the same wave.** Closes `paideia-os#2574` (PFS-07,
chain-head wave PFS-W4).

### Added

- **`src/vol_snapshot.pdx`** —
  `VolSnapshot::snap_chain_walk` real body with new 3-arg
  signature `(root_snap_lba, cb_ptr, cb_ctx) -> count | SnapErr`.
  Walks a parent-linked chain of 4096-byte on-disk "snap-chain
  blocks" via an externally provided block-read authority
  `lpv_bc_read(lba, out_ptr) -> u64`. Intended real-world provider
  is a thin shim over KIND_BLOCK_CACHE's BC_OP_READ cap-invoke
  (paideia-os-side); tests substitute a `.bss`-backed virtual
  block table. 128-step walk cap guards against an unbounded
  chain. Per-step: block read into `.bss` scratch, magic check
  against 0x50445853 ('PDXS'), field decode (generation at +8,
  parent_lba at +16, data_root_lba at +24), callback invocation
  `cb(snap_lba, generation, data_root_lba, parent_lba, cb_ctx)`,
  then follow parent_lba (0 terminates). cb's non-zero return
  flows through unchanged as the walker's own return (callback-
  triggered abort). Preserves the library's "zero cap-invoke
  syscalls in the own call graph" discipline -- `lpv_bc_read`
  remains an unresolved extern in this file's `.o`.
- **`src/vol_snapshot.pdx`** — snap-chain-block on-disk offsets
  (`SCB_D_OFF_MAGIC = 0`, `SCB_D_OFF_GENERATION = 8`,
  `SCB_D_OFF_PARENT_LBA = 16`, `SCB_D_OFF_DATA_ROOT_LBA = 24`;
  `SCB_BLOCK_BYTES = 4096`). Deliberately separate from the
  existing 96-byte snap-metadata record layout
  (`SNAP_D_OFF_*`): the two shapes are orthogonal (the record is
  an in-memory decode buffer the caller supplies to
  `snap_record_parse`; the block is a 4096-byte page the walker
  pulls via the block-read authority).
- **`src/vol_snapshot.pdx`** — new return-code band
  0x0B00..0x0B0F for snap-chain-walk errors, deliberately
  distinct from the 0x0700 band (which belongs to the 96-byte
  record parser): `LPV_SNAP_ERR_READ = 0x0B01` (block-read
  authority failure), `LPV_SNAP_ERR_BAD_MAGIC_SCB = 0x0B02`
  (block magic != 'PDXS'), `LPV_SNAP_ERR_WALK_CAP = 0x0B03`
  (128-step cap exceeded). `LPV_SNAP_WALK_CAP_LIMIT = 128`
  constant documents the cap.
  `LPV_SNAP_CB_ABORT_RESERVED_BAND = 0x0B04` documents the
  convention that callbacks instrumenting their own abort codes
  should pick values outside the 0x0B01..0x0B03 band so the
  caller can discriminate "walker aborted" from "cb aborted".
- **`src/vol_snapshot.pdx`** — two `.bss` scratch slots
  (`lpv_snap_scratch`, 4096 B, the per-step block buffer;
  `lpv_snap_parent_cache`, 8 B, preserves parent_lba across the
  callback invocation without pushing it onto the stack and
  misaligning rsp). Single-writer non-reentrant per this
  library's established `.bss` scratch discipline (same shape as
  `mount_deps.pdx`'s `lpv_mdt_in_degree` / `lpv_mdt_queue` and
  `pdxb_crypto.pdx`'s `lpv_argon2_scratch`).
- **`tests/test_snap_chain_walk.pdx`** (new file) —
  `TestSnapChainWalk::test_snap_chain_walk_run()` four-case
  correctness matrix:
  (1) linear chain of 3 (`100 -> 200 -> 300 -> 0`); expect
      `rax == 3` with cb logging `[100, 200, 300]` and generations
      `[1, 2, 3]`.
  (2) bad-magic root block (LBA 100 holds magic `0xDEADBEEF`);
      expect `rax == LPV_SNAP_ERR_BAD_MAGIC_SCB` (0x0B02) with
      `cb_count == 0`.
  (3) callback aborts at step 2 (mode 1 chain + `tcw_abort_on=2`);
      expect `rax == 0xB099` (cb's abort sentinel), `cb_count == 2`,
      log `[100, 200]`.
  (4) walk-cap exceeded (synthetic 129+-link chain via mode-4
      mock: `parent = lba + 1`, never terminates); expect
      `rax == LPV_SNAP_ERR_WALK_CAP` (0x0B03), `cb_count == 128`.
  Mock KIND_BLOCK_CACHE substituted via test-local `lpv_bc_read`
  (same symbol the walker's `.o` has as an unresolved extern;
  mode-driven synthesis from `.bss`-backed state rather than
  materializing 128 full 4096-byte blocks). Returns 0 on all-pass
  or the 1-based ordinal of the first failing case per the shared
  M4 return-code convention (`tests/README.md`).

### Changed

- **`src/vol_snapshot.pdx`** — module header rewritten to
  document the PFS-07 landing: the new signature, the snap-chain
  block on-disk layout, the external block-read authority
  contract, the 0x0B00..0x0B0F return band, and the orthogonality
  with the existing 96-byte snap-metadata record layout.

### Breaking (symbol-level)

- **`snap_chain_walk` signature changes from 5 args to 3 args.**
  The one in-tree caller (`mount.pdxfs/src/snapshot_wire.pdx`)
  was explicitly flagged in `mount.pdxfs/CHANGELOG.md` as being
  reachable only once this body lands; main's wave-closing
  commit in the paideia-os parent repo must bump the submodule
  pointer AND adapt that caller (or re-stub its passthrough)
  in the same wave. No other callers exist in the paideia-os
  tree as of 2026-10-11.

### Notes

- Encoder-pitfall discipline: no `test rN,rN`; no `add reg,[mem]`;
  no 2-op `imul reg,imm` (the test's `data_root = lba * 7`
  synthesis uses 3-op `imul rax,rdi,7`, matching
  `mount_table_snapshot.pdx`'s established 3-op stride compute);
  no multiline `pub let =`; no reserved labels (`loop`/`if`/`let`;
  all labels prefixed `scw_` or `tcw_`); 128 compared via
  `mov rax,128; cmp rN,rax; jae ...` to sidestep imm8 sign-extend.
- The walker is single-writer non-reentrant: a callback that
  itself calls `snap_chain_walk` would corrupt
  `lpv_snap_scratch` + `lpv_snap_parent_cache`. This matches the
  library's established `.bss` scratch discipline; nested walks
  are a v2.x discussion.

## 1.1.6 — 2026-10-11 (PFS-06 / paideia-os#2573: real Kahn's-algorithm body for mount_table_sort_by_deps)

**Patch bump — additive constants + a real body replacing a
previously-stubbed fail-closed sentinel. Callers that already
treated the stub's `LPV_ORDER_ERR_NOT_IMPL` return as "sort
unavailable" and fell back to insertion order remain correct
(the new real body returns `LPV_ORDER_OK` instead, with a valid
topological order) and no byte-level API shape changes.** Closes
`paideia-os#2573` (PFS-06, chain-head wave PFS-W3).

### Added

- **`src/mount_deps.pdx`** —
  `MountDeps::mount_table_sort_by_deps` real body implementing
  Kahn's algorithm over 40-byte `MountTableEntry` summaries
  (`MTE_OFF_MOUNTPOINT_VNODE_IDX = 0`,
  `MTE_OFF_ROOT_VNODE_IDX = 8`, as in
  `src/mount_table_snapshot.pdx`). Dependency edge: entry V must
  mount before entry M iff `V.root_vnode_idx ==
  M.mountpoint_vnode_idx` -- the direct-nested-mount relation
  the live `_mount_table[]` already carries. On a cycle (any
  node unreachable from an in-degree-0 seed), returns
  `LPV_ORDER_ERR_CYCLE` (0x0A01, previously unreachable from
  the identity-order stub).
- **`src/mount_deps.pdx`** — `LPV_ORDER_ERR_TOO_MANY_ROWS`
  (0x0A05) fail-closed sentinel for inputs exceeding the
  fixed-size work array's 128-row cap; `LPV_MOUNT_SORT_FAIL`
  (0x0A05, numerically-identical alias) preserving the PFS-06
  `MOUNT_SORT_FAIL` sentinel-name contract. `LPV_MDT_MAX_ROWS`
  (128) public constant documenting the cap.
- **`src/mount_deps.pdx`** — two 128-slot u64 `.bss` scratch
  arrays `lpv_mdt_in_degree` and `lpv_mdt_queue` (1024 B each)
  carrying the Kahn's in-degree table + FIFO ready-queue.
  Single-writer non-reentrant per this library's established
  `.bss` scratch discipline (same shape as
  `pdxb_crypto.pdx`'s `lpv_argon2_scratch`).
- **`tests/test_mount_sort.pdx`** (new file) --
  `TestMountSort::test_mount_sort_run()` five-case correctness
  matrix: (1) linear chain A → B → C in input order, (2)
  diamond A → {B, C} → D with D nested under B, (3)
  reversed-input chain [D, C, B, A], (4) two-node cycle
  A ↔ B, (5) empty table. Returns 0 on all-pass or the 1-based
  ordinal of the first failing case per the shared M4
  return-code convention (`tests/README.md`).

### Changed

- **`src/mount_deps.pdx`** — module header updated to document
  the real sort relation, the two `.bss` work arrays, the
  fail-closed `LPV_MOUNT_SORT_FAIL` sentinel, and the
  reserved-for-now `deps_ptr` / `deps_count` arguments (a future
  caller plumbing explicit `mount-before` / `mount-after` /
  `mount-requires` edges from `mount_deps_parse` output will
  layer them on top of the pure vnode-prefix sort).

### Notes

- The sort is deterministic: Kahn's seeds its ready-queue in
  input index order and dequeues FIFO, so a cycle-free run on
  a chain presented in-order emits a stable identity ordering;
  the five-case test matrix relies on this determinism rather
  than accepting any valid topological order.
- `deps_ptr` / `deps_count` arguments remain reserved: current
  callers pass `(0, 0)` and get the pure-vnode-prefix sort;
  no caller in the paideia-os tree consults them today.

## 1.1.5 — 2026-09-02 (R91-XREPO.M1 Phase D: surface satellite-runtime NO_SIGNER upward)

**Patch bump — additive error-sentinel surfacing; every v1.1.4 API
surface remains byte-for-byte compatible for callers using the
`!= 0` failure idiom.** Closes R91-XREPO.M1 Phase D per
`design/infrastructure/satellite-runtime-shim.md` §3.2 + §5 Step 6
+ §8 R4 in the paideia-os repo.

### Fixed

- **`src/pdxb_sign.pdx`** — `pdxb_sign_superblock` and
  `pdxb_sign_inode_tail` previously mapped ANY non-zero return from
  the `MlDsa65::sign` intrinsic to a single generic
  `PDXB_SIGN_ERR` sentinel (`0xFFFFFFFFFFFFFFFF`). In a satellite
  build the sign FFI thunk is
  `paideia-satellite-runtime::mldsa65_sign_runtime_entry`, a
  fail-closed stub that ALWAYS returns
  `PDX_MLDSA_ERR_NO_SIGNER = -6` (added deliberately outside the
  intrinsic's preexisting `-1..-5` band). Swallowing that specific
  return code inside the generic `PDXB_SIGN_ERR` translation defeated
  its whole purpose — a caller could not tell "there is no signer in
  this build" from "the intrinsic was called and rejected its
  inputs" (§8 R4: "fail-closed signer masquerading as success"). Both
  entry points now discriminate `-6` first (`mov r10,
  0xFFFFFFFFFFFFFFFA; cmp rax, r10; je no_signer`), returning a new
  distinct `PDXB_SIGN_ERR_NO_SIGNER` sentinel with the same numeric
  value (0xFFFFFFFFFFFFFFFA = -6 as u64); any other non-zero return
  continues to translate to `PDXB_SIGN_ERR`. The discrimination pattern
  mirrors `pdxb_crypto.pdx::pdxb_dek_unwrap`'s own `-3` tag-mismatch
  discrimination (v1.1.0).

### Added

- **`src/pdxb_sign.pdx`** — `PDXB_SIGN_ERR_NO_SIGNER : u64 =
  0xFFFFFFFFFFFFFFFA` public sentinel constant + expanded module
  header documenting the three-return-value contract (success 3309,
  `PDXB_SIGN_ERR_NO_SIGNER`, `PDXB_SIGN_ERR`) both sign entry points
  now honour.
- **`src/lpv_errors.pdx`** — `LPV_E_SIGN_NO_SIGNER : u64 = 0x0503`
  (in the existing 0x0500..0x05FF signing band) as the banded
  companion to `PDXB_SIGN_ERR_NO_SIGNER` for callers using the
  `LPV_E_*` idiom, plus `lpv_msg_sign_no_signer : [u8; 17] = "sign:
  no signer\0\0"` for a future `lpv_strerror` table entry.
- **`doc/libpdx-volume.pdxdoc`** — SYNOPSIS names both
  `PDXB_SIGN_ERR` and `PDXB_SIGN_ERR_NO_SIGNER`; API section for the
  two sign entry points documents the new three-sentinel return
  contract explicitly and cross-references
  `LpvErrors::LPV_E_SIGN_NO_SIGNER`.

### Consumer impact at this landing

None. No satellite tool currently uses signing at runtime —
`mkfs.pdxfs`, `mount.pdxfs`, and `umount.pdxfs` all default to the
PUBLIC key path (used only to compute `sig_key_hash` via BLAKE3);
`pdxb_sign_superblock` is defined here but never called from any
existing satellite. The surfacing exists so the moment a signing
consumer lands (e.g. a future `fsck.pdxfs` or `pkg.paideia-os`
manifest signer targeting a satellite build), it sees the distinct
sentinel rather than a generic error.

### Compatibility

Additive-only. A caller checking `!= 0` for failure sees the same
failure verdict; only the specific sentinel value changes from
`0xFFFFFFFFFFFFFFFF` to `0xFFFFFFFFFFFFFFFA` on the NO_SIGNER path.
`pdxb_sign_superblock_traced` passes through its untraced
counterpart's `rax` unchanged, so the new sentinel surfaces through
that entry point automatically. The `pdxb_verify_*` functions are
unaffected (still fail-closed stubs returning
`PDXB_VER_ERR_NOT_IMPLEMENTED`).

References: R91-XREPO.M1 Phase D; paideia-as#1348;
`design/infrastructure/satellite-runtime-shim.md` §3.2, §5 Step 6,
§8 R4 (paideia-os).

## 1.1.4 — 2026-09-02 (Phase C: `--extra-archive` uniform-invocation contract)

**Patch bump — additive, accepted-and-stored `tools/build.sh` flag;
every existing invocation still works unchanged.** Part of the
paideia-os#2226 satellite-runtime-shim Phase C landing that adds
`--extra-archive PATH` to the four satellite `build.sh` scripts
(mkfs.pdxfs, mount.pdxfs, umount.pdxfs, and this repo). This library
ships no runnable ELF of its own (build.sh emits per-module
`build-out/*.o` objects for downstream satellites to link against via
`--extra-obj-dir`), so at this landing the flag is parsed-and-stored
but not consumed inside this repo — it exists so a downstream invoker
(a satellite build wrapper, or the `tests/smoke/consumer_e2e.sh`
end-to-end runner) can pass the same argument vector to every
satellite's `tools/build.sh` — including this one — without
special-casing.

### Added

- **`--extra-archive PATH` (repeatable)** on `tools/build.sh`. Same
  bounds-check discipline as the other three satellites (a bare
  `--extra-archive` with no following PATH exits 2 with
  `--extra-archive requires an argument`). Paths are appended to a
  bash `EXTRA_ARCHIVES=()` array. Consumed by a future landing that
  adds a link step here (e.g. a self-contained test-driver ELF); until
  then the array is inert.

### Invocation (uniform across all four satellites)

```
# Sibling satellites (mkfs/mount/umount) consume the archives at their
# final ld link; this repo accepts the flag for invocation uniformity.
bash tools/build.sh \
  --extra-archive $HOME/Development/PaideiaOS/tools/paideia-as/target/release/libpaideia_satellite_runtime.a \
  --extra-archive $HOME/tmp/libpdx-audit/build-out/libpdx-audit-satellite.a
```

References: paideia-os#2226, paideia-as#1348, libpdx-audit#19, design
doc `design/infrastructure/satellite-runtime-shim.md` §4.1 + §5 Step 5.

## 1.1.3 — 2026-09-02 (patch: rename tests-*.o `run` symbols per-test)

**Patch release** closing #35: build-out shipped 3 test objects each
defining an unnamespaced top-level `run` symbol, causing satellite
tools that link against libpdx-volume via `--extra-obj-dir` to hit
`multiple definition of 'run'` at final ld. Source-only rename; no
library API surface affected.

### Fixed

- **#35** — renamed `run` in `tests/test_pdxb_roundtrip.pdx`,
  `tests/test_pdxb_sigverify.pdx`, `tests/test_mount_table_snapshot.pdx`
  to `test_pdxb_roundtrip_run` / `test_pdxb_sigverify_run` /
  `test_mount_table_snapshot_run` respectively (matches the
  reserved-label prefix discipline every non-test module already
  follows). Test-runner callers were already invoking via external
  driver, so no in-tree caller updates needed. Build-out's
  `tests-*.o` regenerated with the new symbol names; satellites
  linking against `build-out/` no longer collide.

## 1.1.2 — 2026-09-02 (patch: additive superblock setter accessors)

**Patch release** closing one Phase-2 accessor-coverage finding against
the v1.1.1 superblock accessor surface. Source-only, additive
changes; every v1.1.1 API surface remains byte-for-byte compatible.

### Added

- **#34** `src/pdxb_superblock.pdx` — six new write accessors
  symmetric to the existing read accessors on `PdxbSuperblockSummary`
  (176-byte decoded layout), closing an accessor-parity gap where
  the getters exist but the setter siblings did not:
  - `pdxb_sb_set_itable_lba`      (SBS_OFF_ITABLE_LBA,     +56)
  - `pdxb_sb_set_itable_bcount`   (SBS_OFF_ITABLE_BCOUNT,  +64)
  - `pdxb_sb_set_alloc_lba`       (SBS_OFF_ALLOC_LBA,      +72)
  - `pdxb_sb_set_alloc_bcount`    (SBS_OFF_ALLOC_BCOUNT,   +80)
  - `pdxb_sb_set_journal_lba`     (SBS_OFF_JOURNAL_LBA,    +88)
  - `pdxb_sb_set_journal_bcount`  (SBS_OFF_JOURNAL_BCOUNT, +96)
  Each is a 1-store leaf mirroring the shape of the existing
  `pdxb_sb_set_total_blocks` / `pdxb_sb_set_root_inode` siblings:
  `mov [rdi + SBS_OFF_*], rsi; xor rax, rax; ret;`. Signature
  `(u64, u64) -> u64 !{mem} @{}` matches the other setters (return
  slot cleared to 0). Inserted between `pdxb_sb_set_total_blocks`
  (+48) and `pdxb_sb_set_root_inode` (+120) to preserve on-disk
  offset ordering in the setter section.

### Deferred

- `pdxb_sb_set_data_lba` (+104), `pdxb_sb_set_data_bcount` (+112),
  and `pdxb_sb_set_sig_key_hash_word` are still missing setter
  siblings for existing getters. Not in the scope of #34 (which
  enumerated only the itable/alloc/journal six); flagged to main for
  a follow-up ticket if full accessor parity is desired.

## 1.1.1 — 2026-09-02 (patch: quota input-contract + arithmetic-wrap guard)

**Patch release** closing two Phase-2 audit findings against the v1.1.0
quota subsystem. Source-only changes; every v1.1.0 API surface remains
byte-for-byte compatible. Both `pdxb_quota_check` and `pdxb_quota_commit`
keep their `(u64, u64, u64, u64) -> u64` / `(u64, u64, u64) -> u64`
signatures unchanged — only the first parameter's spelling and the
enforcement helper's overflow behaviour move.

### Fixed

- **#32** `pdxb_quota_check` / `pdxb_quota_commit` — parameter renamed
  from `quota_row_ptr` to `quota_summary_ptr` (source-only; ABI
  unchanged). The name previously suggested the raw on-disk 64-byte
  row, but both helpers actually operate on the decoded 88-byte
  summary layout produced by `pdxb_quota_row_parse` (the field
  offsets loaded inside the bodies are the `PDXQ_OFF_*` summary
  family, not `PDXQ_D_OFF_*`). Passing a raw on-disk row silently
  misread `blocks_used` / `blocks_hard` from the wrong offsets while
  the mov_d (u32) magic gate at +0 still accidentally observed `PDXQ_MAGIC`
because both layouts store the identical 4-byte magic at their own +0.
  Fix: parameter rename + a shared `INPUT-CONTRACT` header block
  above the two functions + a new `==== QUOTAS` section in
  `doc/libpdx-volume.pdxdoc` + a new `§11.9` in
  `design/architecture.md` documenting the two-layout distinction and
  a worked parse → check → commit → re-encode call example.
- **#33** `pdxb_quota_check` — overflow guard on
  `blocks_used + block_delta`. The pre-fix body added `rsi` into
  `r10` and fell straight through to `cmp r10, blocks_hard`; a
  `block_delta` large enough to wrap `r10` past 2^64 would let a
  wrapped value pass or fail the cmp incorrectly. v1.1.1 inserts
  `jb lpv_qc_overflow_refuse` immediately after the `add`, and the
  new label returns `LPV_QUOTA_HARD_EXCEEDED` (the same sentinel a
  normal hard-limit refusal returns; a distinct code was not
  introduced because caller remediation is identical). `jb` is the
  paideia-as encoder-preferred spelling of jump-if-carry, mirroring
  `kernel/core/syscall/ptr_check.pdx:56`'s `va + len` wrap guard.
- Sibling `pdxb_quota_commit` already handled the negative-delta
  underflow case via a shift + cmp + xor clamp (v1.1.0 landing;
  unchanged at v1.1.1).

### Documentation

- `doc/libpdx-volume.pdxdoc` — new `==== QUOTAS` section with the
  side-by-side raw-row-vs-summary offset tables and a worked
  parse → check → commit → re-encode composition example; VERSION
  block bumped and prefixed with the v1.1.1 changelog stanza.
- `design/architecture.md` — new `§11.9 Quota check/commit input
  contract (v1.1.1 clarification)` covering the two offset families,
  the silent-mismatch failure mode, the source-only rename, the
  arithmetic-wrap guard, and the encoder-preferred `jb` spelling
  precedent.
- `src/pdxb_quota.pdx` — new `INPUT-CONTRACT` block above the two
  helpers plus updated per-function headers pointing at the new
  `.pdxdoc` and architecture-doc sections; module header's
  paideia-as encoder-notes list a bullet for the `jb`/overflow-refuse
  pattern.

### Release manifest

- `release/manifest.pdxsig.txt` — `package-version` 1.1.0 → 1.1.1;
  `package-release` LV.M1-M6 → LV.M7; `source-tag` v1.1.0 → v1.1.1.
  Every `<BLAKE3-*>` slot stays a placeholder; the dual-sign +
  mirror-push external gates (paideia-as toolchain in CI,
  `pkgs.paideia-os` endpoint, release-line ML-DSA-65 seed key
  custody) are unchanged from v1.1.0.

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
