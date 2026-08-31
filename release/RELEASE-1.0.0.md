# libpdx-volume v1.0.0 — release note + mirror-push workflow (M5-001)

**Repo:** github.com/paideia-os/libpdx-volume
**Wave:** R53 shared library
**Version at first release:** 1.0.0
**Upstream policy:** `design/tooling/plan.md` §6.3 (paideia-os) — package
repository layout; `design/02-development-environment.md` §1140 + §1164
(paideia-os) — hybrid Ed25519+ML-DSA-65 signing, release-line key
custody; `design/tooling/volume-tooling-ux.md` §9.4 (paideia-os) —
M5-001 scope.

This document is both the **release note** for what v1.0.0 ships and
the operator runbook for cutting the signed release and pushing it to
the paideia-os package mirror at
`https://pkgs.paideia-os/main/libpdx-volume/1.0.0/`. The workflow
mirrors `libpdx-audit`'s own `release/RELEASE.md` (this org's other
R49/R53-era satellite library, first through M5) — see that file for
the worked template this one follows, and see this file's §5 for the
one substantive addition this repo's own scope requires over that
template.

The actual `git tag v1.0.0` + `git push` is a **manual step main
performs separately from this milestone** — see §6. This document
describes exactly what that tag would contain so a future operator (or
main, later) can cut it without re-deriving scope from STATUS.md and
five milestones of design-doc flags.

---

## 1. What v1.0.0 ships

Everything landed at M1..M4 (see `CHANGELOG.md` for the itemised list,
`STATUS.md` for the per-issue checklist):

- **`VolKind::vol_kind_narrow`** — real validation + passthrough over
  `KIND_VOLUME`'s op catalog (`vol_kind_mint` remains a documented
  stub — no ring-3-reachable mint syscall exists yet).
- **`PdxbSuperblock::pdxb_parse_superblock` /
  `pdxb_encode_superblock`** — the full PDXB v1 4096-byte superblock
  codec, cross-checked byte-for-byte against
  `design/filesystem/volume-fs-substrate.md` §2.1 and
  `src/tools/mkfs-pdxb/main.pdx` (paideia-os).
- **`MountTable::mount_table_row_parse`** — the `KIND_PDXFS_MOUNT_TABLE`
  singleton row parser (matches R53-PREP-001).
- **`MountTableSnapshot::mount_table_snapshot`** — the live
  `_mount_table[8]` per-slot walker (R16-M1-005 frozen layout).
- **`PdxbSign::pdxb_sign_superblock` / `pdxb_sign_inode_tail`** — real
  ML-DSA-65 signing via the paideia-as `MlDsa65::sign` intrinsic (the
  first real, non-test caller of that intrinsic found anywhere in the
  paideia-os / paideia-as tree at M3 landing time).
- **Three test drivers** (`tests/test_pdxb_roundtrip.pdx`,
  `tests/test_pdxb_sigverify.pdx`, `tests/test_mount_table_snapshot.pdx`)
  exercising every real (non-stub) body above.
- **`doc/libpdx-volume.pdxdoc`** — the source-form user-facing
  documentation this milestone adds.

## 2. What v1.0.0 explicitly does NOT ship (deferred)

Consumers relying on this library at v1.0.0 must know these gaps are
real and by design, not oversights:

- **`vol_kind_mint`** — permanently a stub until `KIND_VOLUME` gains a
  ring-3-reachable mint syscall (`design/architecture.md` §7).
- **`vol_kind_narrow`'s kernel-enforced derivation** — today's body is
  validation + passthrough; no `cap_narrow` primitive exists anywhere
  in the kernel tree for `KIND_VOLUME` (`design/architecture.md` §5.1).
- **`PdxbSign::pdxb_verify_inode_tail`** — a fail-closed stub; no
  `mldsa65_verify` intrinsic exists in paideia-as v0.24.0
  (`design/architecture.md` §8.4). `tests/test_pdxb_sigverify.pdx`
  asserts the stub's sentinel, not a real sign-then-verify round trip.
- **Real M4-002 sig-verify coverage** — blocked on the same missing
  verify intrinsic; tracked as a follow-up test once it lands.
- **Dual-signed `manifest.pdxsig` + mirror push** — see §5 below; this
  is the one item this milestone (M5-001) lands the *source form* of
  but does not execute.

## 3. Substrate readiness (blocking the actual signed release)

**S1 — paideia-as toolchain ≥ 0.24.0-mldsa65-sign reachable.** The
release build invokes `paideia-as build` to compile `src/*.pdx` and
`tests/*.pdx`, and `paideia-pq-sign::sign_release_artifact` for the
dual-signature step. `MlDsa65::sign` (the intrinsic `pdxb_sign_
superblock` / `pdxb_sign_inode_tail` call) already ships at v0.24.0;
the higher toolchain floor `libpdx-audit` documents (v0.33-crypto-kdf)
is not a requirement here — this library never touches Argon2id or
ChaCha20-Poly1305. STATUS.md tracks the toolchain version this repo is
tested against.

**S2 — `pkgs.paideia-os` mirror endpoint reachable.** Same mirror,
same non-existent-as-of-R53-close status `libpdx-audit`'s runbook
documents. Until it stands, the release is "cut but not mirrored" —
the signed `manifest.pdxsig` still lands in the GitHub release
attachment set for out-of-band consumers.

**S3 — a live ML-DSA-65 release-line seed key.** Unlike `libpdx-audit`
(whose own release note does not need to call this out separately,
since its dual-sign step is generic infrastructure), this repo's OWN
signing helpers (`pdxb_sign_superblock`, `pdxb_sign_inode_tail`)
already surface the "no seed key lives in this repo" discipline at the
library-code level (`design/architecture.md` §8.2) — the SAME
discipline applies one level up, to the release manifest's own
dual-sign pass. `manifest.pdxsig` is left with the
`SIGNATURE_PLACEHOLDER_PENDING_LIVE_SIGN` sentinel in every signature
slot precisely because that key material is release-line custody
(hardware-backed TPM 2.0 / cloud KMS per `design/
02-development-environment.md` §1164), never repo-resident.

**S4 — `doc` M2 reachable.** The compiled `.pdxdoc` at
`/pkgs/libpdx-volume-1.0.0/doc/libpdx-volume.pdxdoc` is produced by the
`doc compile` subcommand of the `doc` tool at doc.M2 (not landed as of
this milestone). The source form at `doc/libpdx-volume.pdxdoc` in this
repo is the input; consumers render it verbatim until then.

---

## 4. Cut-a-release procedure

Identical shape to `libpdx-audit`'s runbook (same tooling, same
release-line key custody). Reproduced here with this repo's own
artifact names.

**Pre-flight.**

    git fetch origin
    git switch main
    git pull --ff-only
    git status                    # MUST be clean
    gh issue list --milestone M5 --state open --repo paideia-os/libpdx-volume
                                  # MUST be empty

**Step 1 — Version bump + CHANGELOG close.** Already done at M5-001 —
`CHANGELOG.md`'s `## 1.0.0` entry is the one a future tag points at.

**Step 2 — Tag.** (Manual, main-performed — see §6; NOT run as part of
this milestone.)

    git tag -a v1.0.0 -m "libpdx-volume v1.0.0 — R53 M1..M5 close"
    git push origin v1.0.0

**Step 3 — Build the compiled artifact set.**

    paideia-as build src/vol_kind.pdx               -o build/libpdx-volume.o
    paideia-as build src/pdxb_superblock.pdx         -o build/libpdx-volume.o
    paideia-as build src/mount_table.pdx             -o build/libpdx-volume.o
    paideia-as build src/mount_table_snapshot.pdx    -o build/libpdx-volume.o
    paideia-as build src/pdxb_sign.pdx               -o build/libpdx-volume.o
    paideia-as link  build/libpdx-volume.o           -o build/libpdx-volume.so
    doc compile       doc/libpdx-volume.pdxdoc       -o build/libpdx-volume.pdxdoc

**Step 4 — Recompute the manifest.**

    paideia-release fill-manifest \
        --source release/manifest.pdxsig.txt \
        --tree   . \
        --tag    v1.0.0 \
        --output build/manifest.pdxsig.filled.txt

**Step 5 — Dual-sign.**

    paideia-release sign \
        --manifest build/manifest.pdxsig.filled.txt \
        --key-ed25519  release-line-ed25519.sk \
        --key-ml-dsa65 release-line-ml-dsa-65.sk \
        --output   build/manifest.pdxsig

**Step 6 — Mirror push.**

    paideia-release mirror-push \
        --repo   https://pkgs.paideia-os/main/ \
        --pkg    libpdx-volume \
        --version 1.0.0 \
        --files  build/libpdx-volume.so \
                 build/libpdx-volume.pdxdoc \
                 caps.decl \
                 build/manifest.pdxsig

Expected mirror layout after push:

    /pkgs/libpdx-volume-1.0.0/
        lib/libpdx-volume.so
        doc/libpdx-volume.pdxdoc
        caps.decl
        manifest.pdxsig
    /bin/  (no entry — libpdx-volume is a library, not a tool)

**Step 7 — Update `index.pdxsig`.** Atomic as part of Step 6, per
`libpdx-audit`'s own runbook.

**Step 8 — GitHub release.**

    gh release create v1.0.0 \
        --title "libpdx-volume v1.0.0" \
        --notes-file CHANGELOG.md \
        build/manifest.pdxsig \
        build/libpdx-volume.so \
        build/libpdx-volume.pdxdoc \
        caps.decl

---

## 5. Consumers who can rely on this release today

Three CLI tools are the declared consumers of this library
(`mkfs.pdxfs`, `mount.pdxfs`, `umount.pdxfs`, per `README.md`'s
"Callers" section) — none exist as repos yet as of M5 close. When one
lands and links `libpdx-volume` v1.0.0, it can rely on:

- The PDXB codec round-tripping any well-formed superblock
  (`pdxb_parse_superblock` / `pdxb_encode_superblock`, fuzz-tested at
  M4-001 over 100000 iterations).
- `mount_table_snapshot` producing byte-accurate output against the
  real, live `_mount_table[8]` kernel array — not a placeholder shape.
- `pdxb_sign_superblock` / `pdxb_sign_inode_tail` producing a real
  ML-DSA-65 signature, GIVEN a caller-supplied 32-byte seed pointer —
  this library resolves no key material itself (§8.2 of
  `design/architecture.md`).

A consumer must NOT rely on:

- `vol_kind_mint` returning anything but the stub sentinel.
- `vol_kind_narrow` producing a kernel-enforced narrower capability
  (it passes `cap_slot` through unchanged today).
- `pdxb_verify_inode_tail` ever returning success — it is fail-closed
  by construction and always refuses.

## 6. Verification (consumer side)

    pkg install libpdx-volume --verify-only     # dry run, no install
    pkg keys show paideia-release-line           # inspect the signer

AND-semantics per the hybrid scheme: both Ed25519 and ML-DSA-65 MUST
verify; either failure REJECTS the package. Not runnable until the
placeholder signature block in `manifest.pdxsig` is replaced by a real
dual-sign pass per §3/§4 above.

---

## 7. What lands at M5-001 (this milestone)

Repo-side, M5-001 lands the source form of the release:

- `CHANGELOG.md` — v1.0.0 entry summarising M1..M5.
- `doc/libpdx-volume.pdxdoc` — source-form `.pdxdoc` for `doc
  libpdx-volume`.
- `release/manifest.pdxsig.txt` — release manifest source form, every
  hash and every signature slot a documented placeholder.
- `release/RELEASE-1.0.0.md` — this document.
- `STATUS.md` — M5-001 marked landed.
- `design/architecture.md` §10 — the dual-sign-deferral rationale.

**Not performed at this milestone:** the git tag itself (main's manual
step, once this landing is reviewed), the actual `paideia-as build`
compile pass, the dual-sign pass (no live seed key in this repo — see
§3 S3 above and `design/architecture.md` §10), and the mirror push
(mirror endpoint does not exist yet — S2 above).
