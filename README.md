# libpdx-volume

paideia-os shared library: `KIND_VOLUME` client helpers, the PDXB
on-disk superblock codec, and the `KIND_PDXFS_MOUNT_TABLE` client-side
view. This is the one library `mkfs.pdxfs`, `mount.pdxfs`,
`umount.pdxfs` (and, later, `df` / `fsck.pdxfs`) all link so the
on-disk wire format and the mount-table row layout are decoded/encoded
in exactly one place rather than once per tool.

## Purpose

R52 lands the *in-kernel* block-substrate: the PDXB superblock format,
the WAL journal, the bitmap allocator, `KIND_VOLUME` / `KIND_SIG_KEY`,
and the boot-time volume probe. What R52 does not land is a
user-facing path to format a device, mount a discovered volume, or
read back what's currently mounted — that gap is closed by three CLI
tools (`mkfs.pdxfs`, `mount.pdxfs`, `umount.pdxfs`) at R53. Those three
tools do not each reimplement the PDXB byte layout or the mount-table
row layout; they all link this library instead, so a wire-format fix
or a signing-algorithm swap is a single edit.

Concretely, this library:

- Wraps the kernel's `KIND_VOLUME` mint/narrow primitives so a caller
  never packs a mint call's arguments by hand (`vol_kind_mint`,
  `vol_kind_narrow`).
- Parses and encodes the 4096-byte PDXB v1 superblock
  (`pdxb_parse_superblock`, `pdxb_encode_superblock`) and signs it
  (`pdxb_sign_superblock`, M3) via the paideia-as `MlDsa65::sign`
  intrinsic.
- Parses the `KIND_PDXFS_MOUNT_TABLE` capability row
  (`mount_table_row_parse`) and walks the live `_mount_table[]` array
  it points at (`mount_table_snapshot`).
- Signs (and, once a verify intrinsic lands, will verify) an inode-tail
  byte range for a future `fsck.pdxfs` (`pdxb_sign_inode_tail`,
  `pdxb_verify_inode_tail`, M3).

## Status

**M1, M2, and M3 landed** (scaffold + module boundary, the
`KIND_PDXFS_MOUNT_TABLE` row-layout parser, the PDXB superblock codec,
the mount-table snapshot walker, `KIND_VOLUME` op-mask narrowing, and
the ML-DSA-65 signing helpers). M4..M5 pending — see
[`STATUS.md`](STATUS.md) for the per-milestone checklist mirroring
`design/tooling/volume-tooling-ux.md` §9.4 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo.

## API surface (M2 + M3)

| Function | Signature | Body |
|---|---|---|
| `VolKind::vol_kind_mint` | `(dev_cap: u64) -> u64` | stub — returns `LPV_STUB_NOT_IMPLEMENTED` (blocked on a ring-3-reachable `KIND_VOLUME` mint syscall) |
| `VolKind::vol_kind_narrow` | `(cap_slot: u64, requested_ops_mask: u64, out_narrowed_cap_slot: u64) -> u64` | **real** — validates `requested_ops_mask` against `KIND_VOLUME`'s op catalog (bits 0..9); passes `cap_slot` through unchanged on a valid mask (no kernel-side `cap_narrow` primitive exists yet); returns `LPV_VK_OK` (0) or `LPV_VK_ERR_BAD_OPS_MASK` (1) |
| `PdxbSuperblock::pdxb_parse_superblock` | `(buf_ptr: u64, buf_len: u64, out_ptr: u64) -> u64` | **real** — decodes every §2.1 field into a 176-byte `PdxbSuperblockSummary`; returns `PDXB_OK` (0) or a `PDXB_ERR_*` code (buf too short / bad magic / bad version / bad block size) |
| `PdxbSuperblock::pdxb_encode_superblock` | `(sb_ptr: u64, out_ptr: u64, out_len: u64) -> u64` | **real** — zero-fills the 4096-byte output then stamps every field back from the summary; returns `out_len` or `PDXB_ENC_ERR_BUF_TOO_SHORT` |
| `MountTable::mount_table_row_parse` | `(row_ptr: u64, out_ptr: u64) -> u64` | **real** — decodes the 64-byte `KIND_PDXFS_MOUNT_TABLE` singleton row into a `MountTableRow` at `out_ptr`; returns `LPV_MTR_OK` (0), `LPV_MTR_ERR_BAD_MAGIC` (1), or `LPV_MTR_ERR_ROW_DEAD` (2) |
| `MountTableSnapshot::mount_table_snapshot` | `(row_ptr: u64, out_ptr: u64, out_cap: u64, out_count_ptr: u64) -> u64` | **real** — walks the live `_mount_table[]` array the singleton row points at, decoding up to `out_cap` `MountTableEntry` slots and writing the count written to `*out_count_ptr`; returns `LPV_MTS_OK` (0), `LPV_MTS_ERR_BAD_MAGIC` (1), or `LPV_MTS_ERR_ROW_DEAD` (2) |
| `PdxbSign::pdxb_sign_superblock` | `(sb_ptr: u64, seed_ptr: u64, out_sig_ptr: u64, out_sig_len: u64) -> u64` | **real** — signs `sb_ptr[0, 696)` via `MlDsa65::sign` and writes the 3309-byte result to `out_sig_ptr` (pass `sb_ptr + 696` to sign in place); returns `3309` or `PDXB_SIGN_ERR` |
| `PdxbSign::pdxb_sign_inode_tail` | `(inode_ptr: u64, tail_offset: u64, tail_len: u64, seed_ptr: u64, out_sig_ptr: u64) -> u64` | **real** — same signing path over `inode_ptr[tail_offset, tail_offset+tail_len)`; deferred consumer (`fsck.pdxfs` does not exist yet) |
| `PdxbSign::pdxb_verify_inode_tail` | `(inode_ptr: u64, tail_offset: u64, tail_len: u64, sig_ptr: u64, sig_len: u64, pub_key_slot: u64) -> u64` | **stub** — no `mldsa65_verify` intrinsic exists in paideia-as v0.24.0; dereferences nothing, always returns `PDXB_VER_ERR_NOT_IMPLEMENTED` |

paideia-as functions return a single `u64` register, so every "returns
a struct" shape in the upstream design doc becomes an out-pointer +
status-code pair here — see `design/architecture.md` §2 for the
rationale and the exact struct-offset tables.

Only `vol_kind_mint` remains a stub after M2: it needs a
ring-3-reachable `KIND_VOLUME` mint syscall that does not exist yet.
`vol_kind_narrow`'s "real" body is validation + passthrough rather than
a kernel-enforced derivation — see `design/architecture.md` §5.1 for
why no such primitive exists anywhere in the kernel tree today.
`mount_table_snapshot` decodes `src/kernel/core/fs/mount.pdx`'s real,
frozen `_mount_table[8]` per-slot layout (R16-M1-005), not the
not-yet-landed per-mount-entry record `volume-tooling-ux.md` §2.2
sketches — see `design/architecture.md` §4.3.

## Callers

**Declared but not yet linked** (per `design/tooling/volume-tooling-ux.md`
§2, these three repos do not exist yet as of this library's M1
landing):

- `mkfs.pdxfs` — will link `pdxb_parse_superblock` / `pdxb_encode_superblock`.
- `mount.pdxfs` — will link `vol_kind_mint` / `vol_kind_narrow` /
  `mount_table_row_parse` / `mount_table_snapshot`.
- `umount.pdxfs` — will link `mount_table_snapshot` to resolve a
  mount-point path to a mount-table slot.

## Further reading

- [`design/architecture.md`](design/architecture.md) — this library's
  own design doc: dependents, wire-format anchors, struct layouts,
  module split rationale, and open assumptions flagged for
  confirmation.
- [`caps.decl`](caps.decl) — the KIND surfaces this library's functions
  are typed against.
- [`STATUS.md`](STATUS.md) — per-milestone landing checklist.
- `design/tooling/volume-tooling-ux.md` §2.4, §9.4 and
  `design/filesystem/volume-fs-substrate.md` §2.1 in the
  [paideia-os](https://github.com/paideia-os/paideia-os) repo — the
  upstream wave-level design.

## License

MIT — see [`LICENSE`](LICENSE).
