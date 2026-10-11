# libpdx-volume — status

**Wave:** R53 (volume tooling — mkfs / mount / umount + shared library)
**Current milestone:** LV.M10 (v1.1.7 patch — PFS-07 /
paideia-os#2574: real `snap_chain_walk` body + 4-case correctness
matrix, closing M3-002 / LV.M3 follow-up on the snap-chain walker).
LV.M9 (v1.1.6 patch — PFS-06 / paideia-os#2573: real Kahn's-algorithm
body for `mount_table_sort_by_deps`, closing M3-003 / LV.M6 follow-up).
LV.M8 (v1.1.2 patch — additive superblock setter accessors) landed.
LV.M7 (v1.1.1 patch — quota input-contract + arithmetic-wrap guard)
landed. LV.M6 (multivol ordering) landed (partial) at v1.1.0, full
sort body at v1.1.6.
**Version:** 1.1.7 (patch on v1.1.6: PFS-07 /
paideia-os#2574 — replace `snap_chain_walk` fail-closed stub with a
real walker over parent-linked 4096-byte on-disk snap-chain blocks,
new 3-arg signature `(root_snap_lba, cb_ptr, cb_ctx) -> count |
SnapErr`, 128-step walk cap, external block-read authority
`lpv_bc_read` as an unresolved extern resolved by a KIND_BLOCK_CACHE
shim at production link time or a test mock at test-harness link
time, new return-code band 0x0B00..0x0B0F for walker errors
(`LPV_SNAP_ERR_READ`/`_BAD_MAGIC_SCB`/`_WALK_CAP`), new
`tests/test_snap_chain_walk.pdx` four-case correctness matrix. One
in-tree caller [`mount.pdxfs/src/snapshot_wire.pdx::snapshot_wire_
list`] flagged for main-side adaptation in the same submodule-bump
wave).
**Version history:** 1.1.5 (patch on v1.1.4: R91-XREPO.M1 Phase D —
surface `paideia-satellite-runtime`'s `PDX_MLDSA_ERR_NO_SIGNER = -6`
fail-closed sentinel upward through `pdxb_sign_superblock` /
`pdxb_sign_inode_tail` as a distinct `PDXB_SIGN_ERR_NO_SIGNER`
sentinel rather than swallowing it into the generic
`PDXB_SIGN_ERR`); 1.1.4 (patch on v1.1.3: additive
`--extra-archive PATH` flag on `tools/build.sh` for
R91-XREPO.M1 Phase C uniform-invocation contract); 1.1.3 (patch on
v1.1.2: closes issue #35 — test-`run` symbol rename); 1.1.2 (patch
on v1.1.1: closes issue #34 in `src/pdxb_superblock.pdx`; release
manifest scaffolded; dual-sign + mirror push deferred — see
`release/RELEASE-1.0.0.md` §3, still applicable at 1.1.6)

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

### M3 — Signing helpers (landed)

- [x] **M3-001** (#7) — `pdxb_sign_superblock` via the paideia-as
      `MlDsa65::sign` intrinsic (`src/pdxb_sign.pdx`, new file). Signs
      `sb_ptr[0, 696)` (volume-fs-substrate.md §2.1's signed range) and
      writes the 3309-byte result to a caller-chosen `out_sig_ptr`
      (pass `sb_ptr + 696` to sign in place). Takes a raw `seed_ptr`
      rather than the issue brief's `sig_key_slot` — `KIND_SIG_KEY`'s
      landed row is a PUBLIC-key handle, not a private signing seed, and
      this library issues zero cap-invoke calls by established
      discipline; see design/architecture.md §8.2 for the full
      rationale and the flag for main. First real (non-test) caller of
      `MlDsa65::sign` found anywhere in the paideia-os/paideia-as tree.
- [x] **M3-002** (#8) — inode-tail sig helpers (`src/pdxb_sign.pdx`),
      used by future `fsck.pdxfs` (deferred consumer, not yet written).
      `pdxb_sign_inode_tail` has a real body (same `MlDsa65::sign` call
      path, no `out_sig_len` gate — matches the issue's literal 5-arg
      signature, flagged for main in design/architecture.md §8.3).
      `pdxb_verify_inode_tail` is a documented STUB: no `mldsa65_verify`
      intrinsic exists in paideia-as v0.24.0 (repo-wide grep empty);
      always returns a nonzero sentinel, dereferences nothing. See
      design/architecture.md §8.4.

### M4 — Tests + fuzz (landed)

- [x] **M4-001** (#9) — parse-encode round-trip fuzz:
      `tests/test_pdxb_roundtrip.pdx`, new file. 100000 (10^5)
      iterations against `pdxb_parse_superblock` /
      `pdxb_encode_superblock` (M2), holding the three parser-gated
      fields (magic, version, block_size) fixed each iteration and
      drawing the other 19 `PdxbSuperblockSummary` fields from a
      64-bit LCG (`state = state * 6364136223846793005 +
      1442695040888963407 mod 2^64`), masking the one 32-bit-on-disk
      fuzzed field (`flags`) to its low 32 bits before the compare.
      Returns 0 / 1 / 2 / `100+field_ordinal` per
      `tests/README.md`'s return-code convention — no literal
      `emit`+`exit`, since this library has no console/print
      capability anywhere in `caps.decl` (see the file's own header
      for the full rationale, flagged for main alongside every other
      M4 driver here).
- [x] **M4-002** (#10) — sig-verify against a known-signed superblock
      fixture: `tests/test_pdxb_sigverify.pdx`, new file. Builds a
      deterministic "known-blank-superblock + zero-signature-
      placeholder" fixture in `.bss` (three stamped header fields,
      the entire signature region left at its zero-init value — the
      established equivalent of a literal `@rodata_bin` embed, which
      does not exist as an attribute in paideia-as) and calls
      `pdxb_verify_inode_tail` (M3-002 STUB) against it, asserting the
      fail-closed sentinel (`PDXB_VER_ERR_NOT_IMPLEMENTED`) comes back
      verbatim. **Flagged for main:** this is NOT a real sign-then-
      verify round trip — no `mldsa65_verify` intrinsic exists in
      paideia-as v0.24.0 (repo-wide grep empty, same finding M3-002
      already documented); a real M4-002 test is blocked on that
      intrinsic landing on the `MlDsa65` trait.
- [x] **M4-003** (#11) — `mount_table_snapshot` correctness matrix:
      `tests/test_mount_table_snapshot.pdx`, new file. Synthetic
      `KIND_PDXFS_MOUNT_TABLE` row + synthetic 8-slot `_mount_table[]`
      image in `.bss`, driven through `mount_slot_count` = 0, 1, 7,
      and 8 (full) via a shared `tmts_run_case` helper; each case
      verifies `out_count` and every decoded entry's five fields.
      Returns 0 / case ordinal (1..4) per `tests/README.md`'s
      return-code convention.

See `tests/README.md` for the full per-file contract, the shared
return-code convention all three drivers use (a `u64` status code, not
a literal print+exit — this library has no console capability), and
why none of the three drivers needs to fault-inject around a syscall
the way `libpdx-audit`'s M4 drivers do (this library issues zero
syscalls anywhere in its own call graph, by established discipline).

### M5 — Signed release (landed)

- [x] **M5-001** — dual-signed release + `.pdxdoc` + mirror push:
      `release/manifest.pdxsig.txt` (new file), release manifest
      source form matching `libpdx-audit`'s own manifest structure
      section-for-section. Every `blake3-256 = <BLAKE3-*>` hash slot is
      a documented placeholder (recomputed from the working tree at
      tag time by the release tool, same convention `libpdx-audit`'s
      own committed manifest uses); every `[signatures]` slot carries
      the literal sentinel `SIGNATURE_PLACEHOLDER_PENDING_LIVE_SIGN`
      instead, since no live release-line ML-DSA-65 seed key exists in
      this repo — the actual dual-sign + mirror-push run is a
      release-time step performed with hardware-backed key custody
      outside this milestone. See design/architecture.md §10 for the
      full rationale and the flag for main. `doc/libpdx-volume.pdxdoc`
      (new file) documents every exported symbol across the library's
      five modules plus both on-wire byte layouts and a LIMITATIONS
      section. `release/RELEASE-1.0.0.md` (new file) is the operator
      runbook + release note covering what v1.0.0 ships, what remains
      deferred, and the substrate readiness gates (S1..S4) blocking an
      actual signed cut. `CHANGELOG.md` (new file) closes with a
      `## 1.0.0` entry summarising M1..M5.

### LV.M1..LV.M6 — Phase-2 AISSUE audit (v1.1.0, landed)

Sixteen tickets (#16..#31) closing gaps identified by a Phase-1 audit
of the v1.0.0 surface. Full breakdown in `CHANGELOG.md`'s v1.1.0
section; per-ticket landing state:

- **LV.M1 polish (#16..#20)**
  - [x] **#16** — `pdxb_verify_superblock` fail-closed stub (blocked on
        `mldsa65_verify` intrinsic).
  - [x] **#17** — `pdxb_superblock_checksum` + `pdxb_verify_checksum`
        real bodies (CRC32C, 256-entry table). New file
        `src/pdxb_checksum.pdx`.
  - [x] **#18** — Field accessors across `PdxbSuperblockSummary` /
        `MountTableRow` / `MountTableEntry` (22 + 7 + 5 = 34 getters,
        10 setters).
  - [x] **#19** — `LPV_E_*` banded namespace + `lpv_strerror`
        scaffold. New file `src/lpv_errors.pdx`. Dispatch table itself
        is a v1.1.x follow-up (all bindings landed).
  - [x] **#20** — `PDXB_ONDISK_BYTES` / `MTE_BYTES` public aliases
        (v1.0.0 already had `SB_SUMMARY_BYTES` / `MTR_SUMMARY_BYTES` /
        `MTE_SUMMARY_BYTES` as `pub let`; this ticket adds the alias
        names the issue brief specified).
- **LV.M2 hardening (#21..#24)**
  - [ ] **#21** — Dual-sign + mirror-push run. Still deferred (three
        external gates: paideia-as toolchain in CI, `pkgs.paideia-os`
        endpoint, release-line ML-DSA-65 seed key).
  - [x] **#22** — `pdxb_sign_superblock_traced` (partial: `audit_
        client_slot == 0` fast-path works; audit-on branch stubs
        until libpdx-audit is link-resolvable).
  - [x] **#23** — `vol_kind_mint_elevate` 3-arg signature landed;
        body stubs until both external blockers (kernel-side mint
        syscall, libpdx-elevate link) close.
  - [x] **#24** — `tests/smoke/consumer_e2e.sh` scaffold with SKIP
        gates for missing consumer tools (mkfs.pdxfs / mount.pdxfs /
        umount.pdxfs don't yet exist as runnable executables).
- **LV.M3 snapshots (#25..#26)**
  - [x] **#25** — `KIND_VOLUME_SNAPSHOT = 0x1A1` typed; `vol_snapshot
        _narrow` real body (validate + passthrough); `vol_snapshot_
        mint` / `pdxb_snap_create` stubs (blocked on kernel-side
        landing).
  - [x] **#26** — `snap_record_parse` real body (96-byte record decode);
        `snap_chain_walk` stub (blocked on block-read authority
        scaffolding). New file `src/vol_snapshot.pdx`.
  - [x] **PFS-07 (paideia-os#2574)** — `snap_chain_walk` real body
        (`src/vol_snapshot.pdx`). Replaces the v1.1.0 5-arg
        fail-closed stub (`volume_cap, snap_head_lba, out_ptr,
        out_cap, out_count_ptr`, returning `LPV_SNAP_ERR_NOT_
        IMPLEMENTED`) with a new 3-arg signature
        `(root_snap_lba, cb_ptr, cb_ctx) -> count | SnapErr` that
        walks a parent-linked chain of 4096-byte on-disk "snap-chain
        blocks" via an externally provided block-read authority
        `lpv_bc_read(lba, out_ptr) -> u64` (unresolved extern,
        resolved at consumer link time by either a real
        KIND_BLOCK_CACHE shim or a test mock -- preserves the
        library's established "zero cap-invoke syscalls in the own
        call graph" discipline, see `caps.decl` closing note).
        128-step walk cap, deliberately-distinct 0x0B00..0x0B0F
        return-code band (`LPV_SNAP_ERR_READ` / `_BAD_MAGIC_SCB` /
        `_WALK_CAP`) separating walker errors from the 0x0700 band
        that belongs to `snap_record_parse`'s 96-byte record parser.
        Snap-chain block layout (`SCB_D_OFF_*`) is orthogonal to
        the 96-byte metadata record layout -- the two shapes
        coexist; a future consolidation is a v2.x discussion. New
        `.bss` scratch slots `lpv_snap_scratch` (4096 B per-step
        block buffer) and `lpv_snap_parent_cache` (8 B,
        parent_lba preservation across the callback invocation
        without stack-pushing-and-misaligning rsp). New file
        `tests/test_snap_chain_walk.pdx` -- four correctness cases
        (linear chain of 3, bad-magic root, callback aborts at
        step 2, walk-cap exceeded via a 129-link synthetic chain)
        returning 0 on pass or 1..4 per the shared M4 return-code
        convention (`tests/README.md`). Mock KIND_BLOCK_CACHE
        substituted by the test file's own `lpv_bc_read` (mode-
        driven synthesizer rather than materializing 128 full
        4096-byte blocks in `.bss`). **Breaking at the symbol
        level**: the one in-tree caller
        `mount.pdxfs/src/snapshot_wire.pdx::snapshot_wire_list` is
        flagged in `mount.pdxfs/CHANGELOG.md` as "reachable only
        once snap_chain_walk gains a real body" -- main's wave-
        closing commit in the paideia-os parent repo must bump
        the libpdx-volume submodule AND adapt that one caller in
        the same wave (or re-stub its passthrough until the new
        signature is wired through).
- **LV.M4 quotas (#27..#28)**
  - [x] **#27** — Per-subject quota row wire format + `pdxb_quota_
        row_parse` / `_row_encode` / `_table_lookup` real bodies.
        New file `src/pdxb_quota.pdx`.
  - [x] **#28** — `pdxb_quota_check` (all four codes: SOFT_EXCEEDED /
        SOFT_GRACE_EXPIRED / HARD_EXCEEDED / OK) + `pdxb_quota_
        commit` (underflow-clamped). Block path only; inode path is
        a v1.1.x follow-up.
- **LV.M5 encryption (#29..#30)**
  - [x] **#29** — `pdxb_kek_derive` / `pdxb_dek_wrap` / `pdxb_dek_
        unwrap` real bodies via Argon2id + ChaCha20-Poly1305
        intrinsics (paideia-as v0.28.0 stdlib crypto.pdx). `pdxb_
        block_encrypt` / `_decrypt` stubs pending paired-block
        metadata layout agreement. New file `src/pdxb_crypto.pdx`.
  - [x] **#30** — PDXB v2 wire format: parser accepts v1 or v2;
        wrapped-DEK / KDF-salt / wrap-nonce accessors real bodies
        over `_reserved[+192, +268)`.
- **LV.M6 multivol ordering (#31)**
  - [x] **#31** — `mount_deps_parse` real body (128-byte per-dep
        entry decode); `mount_table_sort_by_deps` stub with
        distinct `LPV_ORDER_ERR_NOT_IMPL` sentinel (blocked on
        mountall.pdxfs input-shape agreement). New file
        `src/mount_deps.pdx`.
  - [x] **M3-003 / PFS-06 (paideia-os#2573)** —
        `mount_table_sort_by_deps` real Kahn's-algorithm body
        (`src/mount_deps.pdx`). Replaces the identity-order
        `LPV_ORDER_ERR_NOT_IMPL` stub with an in-place topological
        sort over 40-byte MountTableEntry summaries by the direct-
        nested-mount edge `V.root_vnode_idx == M.mountpoint_vnode_idx`:
        two 128-slot u64 `.bss` scratch arrays (`lpv_mdt_in_degree`,
        `lpv_mdt_queue`) carry the in-degree table + FIFO ready-queue,
        single-writer non-reentrant per this library's established
        `.bss` scratch discipline (same as `pdxb_crypto.pdx`'s
        `lpv_argon2_scratch`). New return codes:
        `LPV_ORDER_ERR_TOO_MANY_ROWS` (0x0A05, fail-closed cap at 128
        entries; also surfaced under the alias `LPV_MOUNT_SORT_FAIL`
        preserving the PFS-06 sentinel-name contract) and the newly
        reachable `LPV_ORDER_ERR_CYCLE` (0x0A01, cycle gate on
        `emitted != entry_count`). `deps_ptr` / `deps_count` arguments
        reserved for a future explicit-override caller plumbing deps
        from `mount_deps_parse` output; current callers pass `(0, 0)`
        and receive the pure-vnode-prefix sort. New file
        `tests/test_mount_sort.pdx` -- five correctness cases (linear
        chain, diamond, reversed-input chain, two-node cycle, empty
        table) returning 0 on pass or 1..5 per the shared M4
        return-code convention (see `tests/README.md`).

### LV.M7 — Phase-2 patch (v1.1.1, landed)

Two audit findings closed against v1.1.0's quota subsystem.
Source-only changes; ABI byte-identical to v1.1.0. Full breakdown in
`CHANGELOG.md`'s v1.1.1 stanza; two-layout distinction documented in
`design/architecture.md` §11.9 and `doc/libpdx-volume.pdxdoc`
§QUOTAS.

- [x] **#32** — `pdxb_quota_check` / `pdxb_quota_commit` parameter
      renamed from `quota_row_ptr` to `quota_summary_ptr` in
      `src/pdxb_quota.pdx` to reflect that the helpers operate on the
      decoded 88-byte summary layout (offsets `PDXQ_OFF_*`), not the
      raw 64-byte on-disk row (offsets `PDXQ_D_OFF_*`).
- [x] **#33** — `pdxb_quota_check` overflow guard on
      `blocks_used + block_delta` via `add; jb lpv_qc_overflow_refuse`
      returning `LPV_QUOTA_HARD_EXCEEDED`. Sibling
      `pdxb_quota_commit`'s existing underflow clamp is unchanged.

### LV.M8 — Phase-2 patch (v1.1.2, landed)

Accessor-parity finding closed against v1.1.1's superblock accessor
surface. Source-only additive changes; ABI byte-identical to v1.1.1.
Full breakdown in `CHANGELOG.md`'s v1.1.2 stanza.

- [x] **#34** — six write accessors added to `src/pdxb_superblock.pdx`
      symmetric to the existing read accessors on
      `PdxbSuperblockSummary`: `pdxb_sb_set_itable_lba`,
      `pdxb_sb_set_itable_bcount`, `pdxb_sb_set_alloc_lba`,
      `pdxb_sb_set_alloc_bcount`, `pdxb_sb_set_journal_lba`,
      `pdxb_sb_set_journal_bcount`. 1-store leaves mirroring the
      shape of the existing `pdxb_sb_set_total_blocks` /
      `pdxb_sb_set_root_inode` siblings. Flagged to main: three
      further getters (`data_lba`, `data_bcount`,
      `sig_key_hash_word`) still lack setter siblings; out of scope
      for #34, a follow-up ticket may close the remaining gap.

## Next milestone

All 16 v1.1.0 tickets accounted for; four (#21, #22 partial, #23
partial, #24 partial) have external blockers documented above. The
v1.1.1 patch (LV.M7 above) closed #32 + #33 against the quota
subsystem. The next tempo tick is either (a) close the external
blockers as their substrates land, or (b) file a follow-up wave once
mkfs.pdxfs / mount.pdxfs / umount.pdxfs start landing in the
paideia-os tree so the smoke witness (#24) can run for real.

Deferred to a future patch/minor release (see `CHANGELOG.md`'s semver
policy):

- **`pdxb_block_encrypt` / `pdxb_block_decrypt` real bodies —
  DESIGN CONTRACT LANDED, implementation pending.** The paired-block
  AEAD metadata layout the v1.1.0 M5-001 (#29) landing deferred is
  now frozen in `design/pdxfs/block-crypto-contract.md` in the
  paideia-os repo (PFS-W3 / PFS-05 wave, 2026-10-11, parent
  `paideia-os/paideia-os#2572`). The contract fixes: (a) one DEK
  per volume unwrapped from the superblock `wrapped_dek` slot at
  mount; (b) 12-byte nonce = `volume_prefix[4] || LE_u64(blk_lba)`
  under the pdxfs CoW invariant (§4.1); (c) paired-metadata layout
  at the data-region tail — 1 metadata block per 128 data blocks,
  32-byte records (nonce[12] || tag[16] || flags[1] || reserved[3]);
  (d) three new superblock anchor slots at `sb+268/+276/+284` for
  epoch counter + metadata region start + metadata block count,
  all inside the signed range `[0, 696)`. Real-body follow-up is
  filed as `paideia-os/paideia-os#2730` ([PFS-05-IMPL]); until it
  lands the stub bodies at `src/pdxb_crypto.pdx` L363-381 stay
  fail-closed returning `LPV_CRYPTO_ERR_NOT_IMPL = 0x0901` so no
  caller can accidentally write plaintext to disk under a flag that
  claims encryption. `design/architecture.md` §11.4's "paired-block
  layout agreement" bullet moves from "pending" to "frozen upstream;
  real-body ticket filed" with this landing.
- **Dual-sign + mirror-push run.** Blocked on (a) the paideia-as
  toolchain reachable in CI, (b) the `pkgs.paideia-os` mirror endpoint
  standing (does not exist as of R53 close), and (c) a live
  release-line ML-DSA-65 seed key. See `release/RELEASE-1.0.0.md` §3
  and design/architecture.md §10.
- **`mldsa65_verify` intrinsic — UPSTREAM LANDED, libpdx-volume
  adoption pending.** The intrinsic shipped as
  `paideia-os/paideia-as#1347` (v0.28.1, 2026-09-02); the current
  `tools/paideia-as/` submodule is well past that floor at v0.37.0.
  Both `pdxb_verify_superblock` and `pdxb_verify_inode_tail` continue
  to carry the fail-closed stub bodies at this v1.1.5 landing, and
  `tests/test_pdxb_sigverify.pdx` continues to be the sentinel-only
  driver, pending a dedicated adoption ticket. Cross-repo contract +
  §4.5 real-body skeleton + §5.2 corpus specification live at
  `design/pdxfs/mldsa65-verify-intrinsic.md` in the paideia-os repo
  (parent `paideia-os/paideia-os#2571`); defense-in-depth verify-ACVP
  vectors tracked at `paideia-os/paideia-as#1604`. The gap bullet in
  `design/architecture.md` §8.4 is a frozen archaeology record of
  the pre-v0.28.1 state and will be retired at adoption.
- **`vol_kind_mint` / `vol_kind_narrow`'s kernel-enforced derivation.**
  `M2-004`'s `vol_kind_narrow` landed as validation + passthrough
  rather than a real kernel-enforced narrowing (see
  `design/architecture.md` §5.1) because `KIND_VOLUME` still has no
  `mount`/`flush`/`snapshot` ops and no generic `cap_narrow` primitive
  exists anywhere in the kernel tree for this KIND. Main should track
  whether a future R53 KIND_VOLUME landing adds either, at which point
  `vol_kind_narrow`'s passthrough line (not its signature) needs to
  become a real call-through; `vol_kind_mint` needs a ring-3-reachable
  mint syscall to stop being a stub at all.
- **`doc` M2 compile pass.** The `.pdxdoc` compiled binary form ships
  once `doc`.M2 lands. Until then consumers render the source form at
  `doc/libpdx-volume.pdxdoc` verbatim.

Build not run for M5 — this library's own discipline is main-only
builds; M5-001 adds no new `.pdx` code (only `release/`, `doc/`,
`CHANGELOG.md`, and a `design/architecture.md` §10 addition), so there
is nothing new for `bash tools/build.sh` to compile, but main should
still run it to confirm the M1..M4 source tree this manifest's
`[artifacts.source]` section enumerates still builds clean before any
future tag is cut.

## Upstream design

`design/tooling/volume-tooling-ux.md` §2.4 + §9.4 and
`design/filesystem/volume-fs-substrate.md` §2.1 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo carry the
wave-level rationale and the full milestone breakdown. See
[`design/architecture.md`](design/architecture.md) in this repo for the
internal shape.
