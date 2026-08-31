# libpdx-volume — architecture

**Wave:** R53 shared library
**Repo:** github.com/paideia-os/libpdx-volume
**Upstream design:** `design/tooling/volume-tooling-ux.md` §2.4 + §9.4
and `design/filesystem/volume-fs-substrate.md` §2.1 in
[paideia-os](https://github.com/paideia-os/paideia-os).

This document describes the internal shape of libpdx-volume. It does
not repeat the wave-level rationale from the paideia-os plan doc; read
that first for why volume tooling needs three CLIs plus one shared
library and for the R52/R53 boundary (R52 = in-kernel substrate, R53 =
user-facing path to format/mount/unmount).

## 1. What this library is

libpdx-volume is the single shared client-side library `mkfs.pdxfs`,
`mount.pdxfs`, `umount.pdxfs` (and, later, `df` / `fsck.pdxfs`) all
link. It owns three things:

1. **`KIND_VOLUME` client helpers** (`vol_kind_mint`, `vol_kind_narrow`)
   — thin wrappers so a caller never hand-packs a mint/narrow call's
   arguments.
2. **The PDXB on-disk superblock codec** (`pdxb_parse_superblock`,
   `pdxb_encode_superblock`, and — M3 — `pdxb_sign_superblock`) — the
   single place the 4096-byte wire format from
   `design/filesystem/volume-fs-substrate.md` §2.1 is decoded/encoded.
3. **The `KIND_PDXFS_MOUNT_TABLE` client-side view**
   (`mount_table_row_parse`, and — M2-003 — `mount_table_snapshot`) —
   the single place the mount-table capability row's on-wire bytes are
   decoded.

## 2. Why every "returns a struct" call is actually `(..., out_ptr) -> u64`

`design/tooling/volume-tooling-ux.md` §2.4 sketches this library's
surface at a conceptual level:

```
pdxb_parse_superblock(bytes) → PdxbSuperblockSummary | Err
pdxb_encode_superblock(fields) → [u8; 4096]
```

paideia-as functions return exactly one `u64` register (see any module
in `libpdx-audit`, this org's other satellite library — every public
entry point's signature is `(...) -> u64`; there is no struct-return
or multi-value-return calling convention in the language). This
library therefore implements the design doc's intent as an
**out-pointer + status-code** pair everywhere a struct "return" is
sketched:

```
pdxb_parse_superblock(buf_ptr: u64, buf_len: u64, out_ptr: u64) -> u64
pdxb_encode_superblock(sb_ptr: u64, out_ptr: u64, out_len: u64) -> u64
mount_table_row_parse(row_ptr: u64, out_ptr: u64) -> u64
```

This mirrors the kernel's own convention for row-shaped data (e.g.
`kind_pdxfs_mount_table.pdx`'s row accessors, which return one scalar
field per call rather than a struct) and the shape the M1 issue brief
itself specifies for `pdxb_encode_superblock` and
`mount_table_row_parse`. **Flagged for main:** the issue brief's text
for `pdxb_parse_superblock` reads `(buf_ptr, buf_len) -> PdxbSuperblockSummary`
(two args, struct return) rather than the three-arg out-pointer shape
implemented here; this doc's read is that the two-arg form is
shorthand in the design brief for the same out-pointer convention
every other struct-shaped function in this codebase uses, not a
requirement that paideia-as somehow return an 18-field struct in
`rax`. Confirm this reading before M2-001 implements the real body —
changing the arity later is a breaking API change for `mkfs.pdxfs`,
which links this function at its own M2.

## 3. `PdxbSuperblockSummary` — in-memory decoded struct

The **on-disk** PDXB v1 superblock layout (LBA 0, exactly 4096 bytes)
is frozen at `design/filesystem/volume-fs-substrate.md` §2.1 in
paideia-os and is authoritative; this library never redefines it. What
this library owns is the **in-memory decoded struct**
(`PdxbSuperblockSummary`) that `pdxb_parse_superblock` writes to
`out_ptr` and `pdxb_encode_superblock` reads from `sb_ptr`. The two
layouts differ because several on-disk fields are not 8-byte-aligned
multiples (`uuid` is 16 bytes, `sig_key_hash` is 32 bytes) and this
library's in-memory struct keeps every slot a full aligned `u64` for
simplicity of access from paideia-as (which has no native sub-8-byte
struct-field addressing beyond raw byte offsets).

| Summary offset | Width | Field | On-disk offset (§2.1) | Notes |
|---:|---:|---|---:|---|
| 0   | 8  | `magic`          | `[0,4)`    | zero-extended u32 |
| 8   | 8  | `version`        | `[4,8)`    | zero-extended u32 |
| 16  | 8  | `uuid_lo`        | `[8,16)`   | uuid bytes 0..8 |
| 24  | 8  | `uuid_hi`        | `[16,24)`  | uuid bytes 8..16 |
| 32  | 8  | `block_size`     | `[24,28)`  | zero-extended u32 |
| 40  | 8  | `flags`          | `[28,32)`  | zero-extended u32 |
| 48  | 8  | `total_blocks`   | `[32,40)`  | |
| 56  | 8  | `itable_lba`     | `[40,48)`  | |
| 64  | 8  | `itable_bcount`  | `[48,56)`  | |
| 72  | 8  | `alloc_lba`      | `[56,64)`  | |
| 80  | 8  | `alloc_bcount`   | `[64,72)`  | |
| 88  | 8  | `journal_lba`    | `[72,80)`  | |
| 96  | 8  | `journal_bcount` | `[80,88)`  | |
| 104 | 8  | `data_lba`       | `[88,96)`  | |
| 112 | 8  | `data_bcount`    | `[96,104)` | |
| 120 | 8  | `root_inode`     | `[104,112)`| |
| 128 | 8  | `mount_gen`      | `[112,120)`| |
| 136 | 8  | `snap_head`      | `[120,128)`| |
| 144 | 32 | `sig_key_hash`   | `[128,160)`| 4 consecutive u64 slots (144,152,160,168) |

**Total: 176 bytes, 22 u64 slots** (`SB_SUMMARY_BYTES` /
`SB_SUMMARY_SLOTS` in `src/pdxb_superblock.pdx`). The on-disk
`_reserved` (536 B, offset 160) and `sig` (3400 B, offset 696) regions
are **not** decoded into the summary — no consumer needs them before
M3 signing support lands, and copying 3400 bytes of signature into a
"summary" struct on every parse would defeat the point of a summary.
A future `pdxb_verify_signature` (M3) reads `sig` directly from the
original on-disk buffer, not from the summary.

Offset constants: `PdxbSuperblock::SBS_OFF_*` in
`src/pdxb_superblock.pdx`.

## 4. `MountTableRow` — in-memory decoded struct (issue #2)

**This is the load-bearing design decision in this document — read
carefully, and confirm before relying on it.**

`design/tooling/volume-tooling-ux.md` §2.2 sketches a **per-mount-entry**
row shape for a not-yet-landed `KIND_PDXFS_MOUNT_TABLE` write op:

```
{mount_id: u64, volume_uuid: [u8;16], mount_point_id: u32,
 backend_id: u8, flags: u32, mount_gen: u64,
 invoker_user: [u8;32]} = 64 bytes (design doc's own count; the
 listed field widths actually sum to 73 bytes, not 64 — the doc's
 arithmetic does not close, which is expected: this is a design
 sketch for functionality that has not landed kernel-side yet)
```

That is **not** what exists in the kernel today. What actually landed
at R53-PREP-001 (`src/kernel/core/cap/kind_pdxfs_mount_table.pdx` in
paideia-os) is a **singleton capability metadata row** — one row
describing the `KIND_PDXFS_MOUNT_TABLE` capability itself (a pointer to
the kernel's `_mount_table[]` array, plus a slot count), not one row
per active mount. Quoting that file's own SECTION 1:

```
[+0]   header0: in_use[63:56] | flags[55:32] | gen[31:16] | kind[15:0]
[+8]   header1: reserved_hi[63:32] | res[31:16] | mount_slot_count[15:0]
[+16]  table_row_addr  (u64)   -- runtime address of _mount_table[]
[+24..+56]  reserved (5 x u64 = 40 bytes)
```

64 bytes total, matching this issue's "64-byte row layout" framing
exactly. `KIND_PDXFS_MOUNT_TABLE` is a SINGLETON authority (`PMT_MAX =
1`) precisely because there is exactly one `_mount_table[]` in the
kernel — the per-mount entries themselves live inside that 8-slot,
8-bytes-per-slot array in `core/fs/mount.pdx`, addressed through
`table_row_addr`, not through additional `KIND_PDXFS_MOUNT_TABLE` rows.

**This issue's `mount_table_row_parse` parses the R53-PREP-001 row**
(the capability metadata row), not the design doc's §2.2 sketch (a
future per-mount-entry record that has no landed kernel representation
yet — no mint path, no write op, no field-packing code exists for it
anywhere in the tree). This reading is supported by
`design/tooling/volume-tooling-ux.md` §9.4's own issue list:
`libpdx-volume.M1-002 KIND_PDXFS_MOUNT_TABLE row-layout parser
(matches R53-PREP-001)` — the parenthetical names the exact kernel
file this library's parser matches, and that file has only the
singleton-metadata-row shape.

**Confirm with main before relying on this:** if a future landing
introduces a genuine per-mount-entry row format matching §2.2's sketch
(distinct from the `KIND_PDXFS_MOUNT_TABLE` capability's own metadata
row), `mount_table_row_parse` will need a second entry point (or a
`row_kind` discriminator argument) rather than a signature change to
this one — the two row shapes are not interchangeable and this
function's name should not silently start meaning something else.

### 4.1 `MountTableRow` summary layout

| Offset | Width | Field | Source (row bytes) |
|---:|---:|---|---|
| 0  | 8 | `kind`              | header0 bits `[15:0]` — must equal `0x1A5` |
| 8  | 8 | `in_use`            | header0 bits `[63:56]` — 0 or 1 |
| 16 | 8 | `flags`             | header0 bits `[55:32]` — 24 bits |
| 24 | 8 | `gen`               | header0 bits `[31:16]` |
| 32 | 8 | `mount_slot_count`  | header1 bits `[15:0]` — informational, not validated against `PMT_MOUNT_SLOT_COUNT` (8) at M1 |
| 40 | 8 | `reserved_hi`       | header1 bits `[63:32]` |
| 48 | 8 | `table_row_addr`    | row word 2, verbatim |

**Total: 56 bytes, 7 u64 slots** (`MTR_SUMMARY_BYTES` in
`src/mount_table.pdx`). Row words 3..7 (the kernel's own reserved
footprint) are not decoded — nothing is stamped there at R53-PREP-001,
per that file's own SECTION 1.

Offset constants: `MountTable::MTR_OFF_*` in `src/mount_table.pdx`.

### 4.2 Validation contract

`mount_table_row_parse(row_ptr, out_ptr) -> u64`:

1. **Magic check** — header0's `kind` field (bits `[15:0]`) must equal
   `KIND_PDXFS_MOUNT_TABLE` (0x1A5). Failure: `LPV_MTR_ERR_BAD_MAGIC`
   (1).
2. **Liveness check** — header0's `in_use` byte (bits `[63:56]`) must
   be nonzero. Failure: `LPV_MTR_ERR_ROW_DEAD` (2).
3. On success, decode both header words plus the verbatim
   `table_row_addr` word into `out_ptr` per §4.1 and return
   `LPV_MTR_OK` (0).

**No separate "version" field exists in this row layout** — `kind` is
the row format's only discriminator. This issue's brief asks for
"invalid magic/version" refusal; this parser collapses that to the
single `kind` check because there is nothing else to check. If a
future landing adds an independent row-format version field, this
validation must be revisited — flagged for main.

## 5. `vol_kind_narrow`'s `ops_mask` — a KIND surface that doesn't exist yet

`design/tooling/volume-tooling-ux.md` §2.4 describes `vol_kind_narrow`
as narrowing a `KIND_VOLUME` cap to a subset of `{mount, query, flush,
snapshot}` ops. `src/kernel/core/cap/kind_volume.pdx`'s actual op
catalog (`VOL_OP_*`, ordinals 0..9) as of this M1 landing is:

```
VOL_OP_QUERY_DEVICE_SLOT   0
VOL_OP_QUERY_MOUNT_SLOT    1
VOL_OP_QUERY_UUID_LO       2
VOL_OP_QUERY_UUID_HI       3
VOL_OP_QUERY_ROOT_INODE    4
VOL_OP_QUERY_MOUNT_GEN     5
VOL_OP_QUERY_INODE_COUNT   6
VOL_OP_QUERY_FREE_BLOCKS   7
VOL_OP_QUERY_SIG_KEY_SLOT  8
VOL_OP_DEBUG_PRINT         9
```

Every op is a query; there is no `mount`, `flush`, or `snapshot` op.
`design/tooling/volume-tooling-ux.md` §5.3 itself confirms the gap in
passing — it describes `VOL_OP_QUERY_HANDLE_COUNT` as "a new op added
by R53.M2 to R52's `KIND_VOLUME` op set", i.e. the op catalog this
design wave depends on is explicitly not finished landing. **This is
why `vol_kind_narrow` is a stub at M1** rather than a real
rights-subset check against `R_VOL_ALL` (0x43B) the way
`mount_table_row_parse`'s magic check is real: there is no `mount` bit
to narrow *to* yet. Flagged for main: confirm whether `M2-004` (the
issue that lands `vol_kind_narrow`'s real body, per STATUS.md) should
be re-scoped to rights-only narrowing (`R_VOL_READ` /
`R_VOL_WRITE` / `R_VOL_INVOKE` / ...) rather than the ops-mask shape
the design doc sketches, or whether it should simply wait for the
kernel-side `mount`/`flush`/`snapshot` ops to land first.

## 6. Module split rationale

Three source files, one per public-entry-point family — the same
granularity `libpdx-audit` uses (`audit_record.pdx` / `audit_client.pdx`
/ `audit_broker.pdx` / `audit_hash.pdx`, one module per concern):

- **`src/vol_kind.pdx`** (`VolKind`) — `KIND_VOLUME` mint/narrow. Both
  entry points operate on the same KIND and share the same
  "not-yet-landed op catalog" blocker (§5), so they live together.
- **`src/pdxb_superblock.pdx`** (`PdxbSuperblock`) — the PDXB codec.
  Parse and encode are inverses of the same wire format and share the
  same constant table (`PDXB_MAGIC`, `SBS_OFF_*`), so they live
  together. Signing (`pdxb_sign_superblock`, M3) will likely land in
  its own `src/signing.pdx` once it exists, since it depends on a
  different substrate (the paideia-as `mldsa65_sign` intrinsic) than
  the pure-decode/encode logic here — not created yet because there is
  no M1 stub for it (the M1 issue brief does not list a signing stub).
- **`src/mount_table.pdx`** (`MountTable`) — the mount-table row
  parser. Kept separate from the superblock codec because it decodes a
  capability-table row, not a filesystem wire format, and because it
  is the one M1 function with a real (non-stub) body — worth isolating
  so a reader can find "the thing that actually does something" at M1
  without wading through stub justifications.

No `src/signing.pdx` and no `tests/` content at this landing, matching
the M1 issue brief's explicit scope ("Nothing under `tests/` yet — M4
lands the fuzz/round-trip harness").

## 7. What M1 explicitly does not do

Called out here so a reader of M1 code does not mistake absence for
bug:

- No real `vol_kind_mint` / `vol_kind_narrow` body — both are
  sentinel-returning stubs (§5 explains the `vol_kind_narrow` blocker;
  `vol_kind_mint` additionally needs a ring-3-reachable mint syscall
  that does not exist yet, per `kind_volume.pdx`'s own "no cap-invoke
  op reaches kind_volume_mint" note).
- No real `pdxb_parse_superblock` / `pdxb_encode_superblock` body —
  both are stubs (§2, §3). The parser zeroes its output struct and
  returns success unconditionally; nothing is validated.
- No `pdxb_sign_superblock` at all — not stubbed, not scoped for M1
  per the issue brief.
- No `mount_table_snapshot` — that is `libpdx-volume.M2-003`, a walk
  over the *live* `_mount_table[]` array via `table_row_addr` (decoded
  by this M1's `mount_table_row_parse`), not a repeat of this row
  parser.
- No cap-invoke calls anywhere in this repo. Every function operates
  on caller-supplied raw pointers or cap-slot integers; none of them
  issue a syscall at M1 (see `caps.decl`'s closing note).
