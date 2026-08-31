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

## 3.1 M2-001/M2-002 landing — real parse/encode bodies

`pdxb_parse_superblock` and `pdxb_encode_superblock` (§2, §3 above) now
have real bodies, cross-checked against **two** independent sources
that agree byte-for-byte: `design/filesystem/volume-fs-substrate.md`
§2.1 (the authoritative spec) and `src/tools/mkfs-pdxb/main.pdx`
(paideia-os, R53.M1-001 — the host-side tool that actually WRITES this
layout on disk today, via `mkfs_pdxb_sb_populate`). Both agree on every
offset this library decodes.

**Validation gates.** The M2-001 issue brief asks for "invalid
magic/version/checksum" refusal. There is **no checksum field** in the
on-disk PDXB v1 superblock — §2.1's table has no `checksum` row, and
neither does `mkfs-pdxb/main.pdx`'s mirror of that layout. This
document's read is that the issue brief's "checksum" is generic
template language (the same brief text likely applies across several
libpdx-volume issues) rather than a real field this library must gate
on. In its place, `pdxb_parse_superblock` gates on **`block_size`**
(must equal 4096) — a real on-disk field §2.1 explicitly calls out as
mount-time-refusable ("rejected at mount if different"), giving four
concrete gates: `buf_len >= 4096`, `magic == PDXB_MAGIC`,
`version == 1`, `block_size == 4096`. **Flagged for main:** confirm
there is no separate checksum field this parser should be validating
instead — if the design doc is later amended to add one (e.g. a CRC32C
of the fixed-field region, mirroring the journal block's own `csum`
field at §2.4), this parser's gate list needs a fifth entry.

**`_reserved` non-zero refusal — deliberately NOT implemented.** §2.1's
discipline note says a non-zero `_reserved` byte "indicates a
from-the-future superblock; refuse rather than silently ignore." This
parser does not scan the 536-byte `_reserved` region. Rationale: that
refusal is a **mount-time forward-compatibility policy**, not a
decode-correctness concern — this library's contract is "decode what
the wire format defines," and the mount path (not this codec) is where
policy about future-versioned images belongs, mirroring this repo's
existing "the parser decodes, the caller (mkfs.pdxfs) owns the
PDXB/PDXL refusal-gate policy" split from the M1 landing. **Flagged for
main:** if a future landing wants this refusal at the codec layer
instead, it is a straightforward addition (a 67-iteration qword-OR
loop over `_reserved`) but changes this function from a pure structural
decoder into a policy gate.

**Encoder zero-fill strategy.** `pdxb_encode_superblock` zero-fills the
*entire* 4096-byte output buffer first (one bounded 512-iteration
qword loop) rather than tracking `_reserved` and `sig`'s bounds
separately. This is simpler to verify by inspection than two
narrower zero-fill ranges and costs nothing extra — the eighteen real
field writes that follow overwrite the zeroed bytes at their offsets
regardless.

## 4.3 M2-003 landing — `mount_table_snapshot`, and where the real per-mount-entry layout came from

§4's "confirm with main before relying on this" flag from M1 asked
whether a genuine per-mount-entry record exists anywhere, distinct
from the `KIND_PDXFS_MOUNT_TABLE` singleton row. **It does** — just not
the one `volume-tooling-ux.md` §2.2 sketches.

`table_row_addr` (the singleton row's word at on-disk offset `+16`)
points at `src/kernel/core/fs/mount.pdx`'s `_mount_table[MOUNT_MAX=8]`
array (paideia-os, R16-M1-005, `#574` — frozen well before R53, at
`design/kernel/r16-m1-005-mount-table.md` §2). That array's per-slot
layout is real, frozen, and already load-bearing kernel code (vnode
mount/lookup uses it today):

```
_mount_table[8]: [u64; 8], @align(64), 8 bytes/slot:
  [0, 16)  mountpoint_vnode_idx (u16)
  [16, 32) root_vnode_idx       (u16)
  [32, 40) backend_type         (u8)   NONE=0, TMPFS=1, DEVFS=2,
                                        PROCFS=3, TTY=4, PDXFS_BLOCK=5
  [40, 48) flags                (u8)   bit0 VALID, bit1 ROOT,
                                        bit2 PENDING_UNMOUNT
  [48, 64) _reserved            (u16)
```

This is **not** the `{mount_id, volume_uuid, mount_point_id,
backend_id, flags, mount_gen, invoker_user}` record §2.2 sketches — it
has no `mount_id`, no `volume_uuid`, no `invoker_user`. Those richer
fields belong to a higher-level mount-lifecycle record that, per §4's
original write-up, has landed nowhere in the tree — no mint path, no
write op, no field-packing code. `mount_table_snapshot`
(`src/mount_table_snapshot.pdx`) decodes the REAL, frozen
`_mount_table[]` layout instead of inventing a 32-byte placeholder,
because a real frozen layout existed to find (a `grep` for
`_mount_table` in `core/fs/mount.pdx` surfaces it immediately) and
using it means this function's output is byte-accurate against live
kernel state today rather than a shape nothing produces.

**Confirm with main:** if a future landing introduces the richer §2.2
per-mount record as a genuinely separate structure (e.g. a
`KIND_PDXFS_MOUNT_TABLE` write op that mints per-mount metadata
distinct from `_mount_table[]`'s vnode-layer bookkeeping),
`mount_table_snapshot`'s decode target will need to change, or a
second entry point will be needed — same non-interchangeability caveat
`mount_table_row_parse` already carries for the singleton-vs-per-entry
split.

**Signature.** `mount_table_snapshot(row_ptr, out_ptr, out_cap,
out_count_ptr) -> u64` — a 4-arg out-pointer + status-code shape (not a
"return a Vec" shape, per §2's arity rationale): `out_cap` bounds how
many `MountTableEntry` slots the caller's `out_ptr` buffer holds,
`out_count_ptr` receives how many were actually written
(`min(mount_slot_count, out_cap)`), and the `u64` return is
`LPV_MTS_OK` / `LPV_MTS_ERR_BAD_MAGIC` / `LPV_MTS_ERR_ROW_DEAD` — the
same two failure codes `mount_table_row_parse` uses, by the same
numeric values, since both gate the identical singleton row.

The walk is **unconditional over slot range**, not filtered to
`MOUNT_FLAG_VALID` slots — every slot in `[0, walk_count)` is decoded
and written, empty or not. A `df`/`mount`-style CLI consumer wants to
see empty slots too (e.g. to report remaining mount-table capacity);
filtering by `MTE_OFF_FLAGS & 0x01` is left to the caller.

## 5.1 M2-004 landing — `vol_kind_narrow`'s real body

§5 above (M1) already surfaced the blocker this issue runs into:
`KIND_VOLUME`'s op catalog is query-only, and there is no `mount` /
`flush` / `snapshot` op to narrow *to*. Before writing this issue's
body, a repo-wide grep for a generic capability-op-narrowing primitive
(`*_cap_narrow`, `*_narrow_ops`, or similar) came back with exactly
**one** hit in the entire kernel tree: `kind_ec_query.pdx`'s
`ec_query_row_narrow`. That function is unrelated to this problem — it
clears one bit of a per-row EC-query event-notify bitmap; there is no
generic `cap_narrow` syscall this library could call through for
`KIND_VOLUME`.

Given that, `vol_kind_narrow`'s real body does the one thing this
library can own without a kernel-side derivation surface: it validates
`requested_ops_mask` against the real, frozen op catalog (bits 0..9,
`VK_OPS_VALID_MASK = 0x3FF`) and, on a valid mask, writes `cap_slot`
through to `*out_narrowed_cap_slot` **unchanged** — a documented
passthrough, not a real derivation. This is deliberately the second of
the M2 issue brief's two offered remediations ("do the mask validation
locally and return a placeholder narrowed slot") rather than a bare
stub, because the validation itself is a genuine, real correctness
check today: it catches an out-of-range op request at the client
library boundary rather than letting it reach a syscall that would
refuse it with a less specific error. What it does **not** do is
produce a kernel-enforced narrower capability — `KIND_VOLUME`'s rights
model (`R_VOL_READ` / `WRITE` / `INVOKE` / `REVOKE` / `REFRESH` /
`OBSERVE`) gates whole categories of operations, not individual
`VOL_OP_*` ordinals, so there is no narrower capability a valid
`ops_mask` could actually produce with today's kernel surface.

**Signature change from M1.** The M1 stub was `vol_kind_narrow(vol_cap,
ops_mask) -> u64` (2 args, cap-or-sentinel return). The M2 issue brief
specifies a 3-arg out-pointer shape,
`vol_kind_narrow(cap_slot, requested_ops_mask, out_narrowed_cap_slot)
-> u64`, matching this library's established out-pointer + status-code
convention (§2) rather than the "return a capability value in `rax`"
shape the M1 stub used. This is a breaking API change from M1's
placeholder signature — acceptable because M1's stub was never callable
for anything real (it always returned the sentinel) and no consumer
links against it yet.

**Confirm with main:** when `KIND_VOLUME` gains a real per-op or
per-rights-subset derivation primitive (kernel-side), this function's
passthrough line becomes a real call through that primitive. The
validation gate and the function's signature should not need to change
at that point — only the body between the gate and the return.

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
