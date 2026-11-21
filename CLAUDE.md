# GameSpice Entity

The id space every world object shares. `GSEntity` packs a kind and a serial into one `int` (`id = kind * STRIDE + serial`), `GSEntityTable` hands out ids that are never reused and maps them to nodes, keys and owners, and `GSEntityHandle` is one open entity. GameSpice Combat, GameSpice Net and the games key by these ids.

Read the family [CLAUDE.md](../../CLAUDE.md) and [godot/NOTES.md](../NOTES.md) first.

**The distributable is `addons/gs_entity/`.** It requires [GameSpice Core](../gs-core) and nothing else (`ln -s ../../gs-core/addons/gs_core addons/gs_core`, gitignored).

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | changing the layout or the table: the four load-bearing decisions, the tree guard, lifetimes and sweeping, the unbuilt second layer, why not gs-core |
| [docs/history.md](docs/history.md) | why it exists: the hand-rolled schemes it replaced, and the collision one of them had |

## Layout

| Path | What |
| --- | --- |
| `core/gs_entity.gd` | `GSEntity`: `KIND_*` constants (0 reserved, 1..8), `KIND_NAMES`, `STRIDE`, packing and unpacking |
| `core/gs_entity_table.gd` | `GSEntityTable`: `open`, `close`, `close_owner`, `sweep`, `clear`, lookups by id, node and key, listings, `opened` / `closed` signals |
| `core/gs_entity_handle.gd` | `GSEntityHandle`: one open entity; `node`, owner, `is_alive`, `position`, `position_2d` |
| `examples/entity_selftest.tscn` | the suite |

Paths except `examples/` are in `addons/gs_entity/`.

## Running and testing

The family's two steps ([family CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 120 godot --headless --path . res://examples/entity_selftest.tscn`. Stderr should be empty. After adding a `class_name` here, re-run `--import` in every project that links `addons/gs_entity`.

## Rules that bite

- Kinds are plain `int` constants, not an enum; the numbers are part of the wire format. [design](docs/design.md#the-layout-and-what-is-load-bearing)
- Zero is never a kind: GameSpice Combat reads attacker 0 as "no attacker". [design](docs/design.md#the-layout-and-what-is-load-bearing)
- Serials are never reused; exhaustion (`serial_limit`, default 10^12 - 1, 0 = format ceiling) refuses with `CODE_QUOTA`, never wraps. `kind_limit` defaults to 8, 0 = 9223371; both refuse bad values rather than clamp. [design](docs/design.md#the-layout-and-what-is-load-bearing)
- A new kind is a constant plus a `KIND_NAMES` entry; the suite checks both. [design](docs/design.md#the-layout-and-what-is-load-bearing)
- `open()` before the node is in the tree is normal; keep the `is_inside_tree()` guard in `position()` and `position_2d()`. [design](docs/design.md#positions-before-the-node-is-in-the-tree)
- `close()` frees nothing: close, then free. [design](docs/design.md#lifetimes-close-then-free-then-sweep)
- A node freed without `close()` leaks until `sweep()`; call it once per tick or round. `auto_sweep` stays off by default. [design](docs/design.md#lifetimes-close-then-free-then-sweep)
- `count()` and `ids()` honour `auto_sweep`; the per-kind and handle listings deliberately do not. [design](docs/design.md#lifetimes-close-then-free-then-sweep)
- `GSEntity` and `GSEntityTable` depend on nothing but GameSpice Core; keep them movable. [design](docs/design.md#why-this-is-its-own-repository-and-not-part-of-gs-core)

## Open items

- The shared def / catalogue / limits / spawner base for GameSpice Props, GameSpice NPC and GameSpice Vehicle is designed and not built, and their `*Instance` records do not use `GSEntityHandle` yet. It lands as one pass across the three addons. [design](docs/design.md#the-second-layer-designed-and-not-built)
