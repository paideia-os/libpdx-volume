# libpdx-volume — status

**Wave:** R53 (volume tooling — mkfs / mount / umount + shared library)
**Current milestone:** LV.M6 (multivol ordering) — landed (partial)
**Version:** 1.1.0 (release manifest scaffolded; dual-sign + mirror
push deferred — see `release/RELEASE-1.0.0.md` §3, still applicable at
1.1.0)

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

## Next milestone

All 16 v1.1.0 tickets accounted for; four (#21, #22 partial, #23
partial, #24 partial) have external blockers documented above. The
next tempo tick is either (a) close the external blockers as their
substrates land, or (b) file a follow-up wave once mkfs.pdxfs /
mount.pdxfs / umount.pdxfs start landing in the paideia-os tree so
the smoke witness (#24) can run for real.

Deferred to a future patch/minor release (see `CHANGELOG.md`'s semver
policy):

- **Dual-sign + mirror-push run.** Blocked on (a) the paideia-as
  toolchain reachable in CI, (b) the `pkgs.paideia-os` mirror endpoint
  standing (does not exist as of R53 close), and (c) a live
  release-line ML-DSA-65 seed key. See `release/RELEASE-1.0.0.md` §3
  and design/architecture.md §10.
- **`mldsa65_verify` intrinsic.** `pdxb_verify_inode_tail` stays a
  fail-closed stub and `tests/test_pdxb_sigverify.pdx` stays a
  sentinel-only test until this lands on the `MlDsa65` trait
  (design/architecture.md §8.4).
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
