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
  (`pdxb_parse_superblock`, `pdxb_encode_superblock`), and will sign it
  (`pdxb_sign_superblock`, M3) once the paideia-as `mldsa65_sign`
  intrinsic is linkable.
- Parses the `KIND_PDXFS_MOUNT_TABLE` capability row
  (`mount_table_row_parse`), and will walk the live `_mount_table[]`
  array (`mount_table_snapshot`, M2-003) once a real LIST/READ_ROW
  cap-invoke op exists on that KIND.

## Status

**M1-001 + M1-002 landed** (scaffold + module boundary, and the
`KIND_PDXFS_MOUNT_TABLE` row-layout parser). M1-003..M5-* pending — see
[`STATUS.md`](STATUS.md) for the per-milestone checklist mirroring
`design/tooling/volume-tooling-ux.md` §9.4 in the
[paideia-os](https://github.com/paideia-os/paideia-os) repo.

## API surface (M1)

| Function | Signature | M1 body |
|---|---|---|
| `VolKind::vol_kind_mint` | `(dev_cap: u64) -> u64` | stub — returns `LPV_STUB_NOT_IMPLEMENTED` |
| `VolKind::vol_kind_narrow` | `(vol_cap: u64, ops_mask: u64) -> u64` | stub — returns `LPV_STUB_NOT_IMPLEMENTED` |
| `PdxbSuperblock::pdxb_parse_superblock` | `(buf_ptr: u64, buf_len: u64, out_ptr: u64) -> u64` | stub — zeroes a 176-byte `PdxbSuperblockSummary` at `out_ptr`, returns `PDXB_OK` |
| `PdxbSuperblock::pdxb_encode_superblock` | `(sb_ptr: u64, out_ptr: u64, out_len: u64) -> u64` | stub — returns `PDXB_OK`, writes nothing |
| `MountTable::mount_table_row_parse` | `(row_ptr: u64, out_ptr: u64) -> u64` | **real** — decodes the 64-byte `KIND_PDXFS_MOUNT_TABLE` row into a `MountTableRow` at `out_ptr`; returns `LPV_MTR_OK` (0), `LPV_MTR_ERR_BAD_MAGIC` (1), or `LPV_MTR_ERR_ROW_DEAD` (2) |

paideia-as functions return a single `u64` register, so every "returns
a struct" shape in the upstream design doc becomes an out-pointer +
status-code pair here — see `design/architecture.md` §2 for the
rationale and the exact struct-offset tables.

Only `mount_table_row_parse` has a real body at M1: the 64-byte row
layout it parses was already frozen kernel-side by R53-PREP-001
(`src/kernel/core/cap/kind_pdxfs_mount_table.pdx`), so there is no
upstream KIND surface left to wait on. The superblock codec and the
`KIND_VOLUME` helpers are stubs because they decode/encode a wire
format and an op catalog that either haven't fully landed kernel-side
yet or belong to a library-owned in-memory struct this repo has not
built the real logic for.

## Callers

**Declared but not yet linked** (per `design/tooling/volume-tooling-ux.md`
§2, these three repos do not exist yet as of this library's M1
landing):

- `mkfs.pdxfs` — will link `pdxb_parse_superblock` / `pdxb_encode_superblock`.
- `mount.pdxfs` — will link `vol_kind_mint` / `vol_kind_narrow` /
  `mount_table_row_parse` (and, at M2, `mount_table_snapshot`).
- `umount.pdxfs` — will link `mount_table_snapshot` (M2-003) to resolve
  a mount-point path to a `mount_id`.

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
