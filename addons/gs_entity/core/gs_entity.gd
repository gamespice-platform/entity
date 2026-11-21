@tool
class_name GSEntity
extends RefCounted

## The id space every world object shares, and the arithmetic over it.
##
## [b]This exists because the games each invented it and disagreed.[/b]
## [code]GSCombatManager[/code] keys hitboxes, health, authoritative origins and its
## [code]entity_killed[/code] signal by an [code]entity_id: int[/code] — and nothing
## owned that number. Four games, four schemes: the peer id for players;
## [code]1_000_000 + (instance_id % 1_000_000)[/code] for monsters; a counter per
## player; and the digits parsed out of a [code]"u123"[/code] userid.
## Four id spaces, four spellings of "is this one a player", and one of them
## collidable: two nodes whose engine instance ids differ by a multiple of a million
## register their health over each other, silently, and the loser simply stops taking
## damage.
##
## [b]An id carries its kind, and that is the whole point of the layout.[/b] The
## question asked most often about an entity id is not "which one is it" but "what sort
## of thing is it" — a kill feed deciding whether to write a name, a damage rule
## deciding whether friendly fire applies, a spectator deciding whether this is
## something worth following. Every game answered it with a magic constant and a range
## check. Here it is [method kind_of], and it costs one division.
##
## [codeblock]
## var id := table.open(GSEntity.KIND_NPC, node).value.id
## GSEntity.kind_of(id)        # GSEntity.KIND_NPC
## GSEntity.describe_id(id)    # "npc#1", the first npc a fresh table hands out
## [/codeblock]
##
## [b]Serials are never reused, and that is deliberate.[/b] The shipped practice for
## handles like these is an index plus a generation counter, so a stale handle can be
## told from a live one that happens to occupy the same slot. Reusing nothing gets the
## same guarantee for free: an id that named a dead entity is simply absent from
## [GSEntityTable], for the life of the process, and every lookup that would have
## silently found the wrong object finds nothing instead.

## What sort of thing an id names.
##
## [b]Plain [code]int[/code] constants rather than an [code]enum[/code].[/b] The kind is
## multiplied into an id, sent over the wire inside that id, and compared on the far
## side by code that may be a version behind; an enum invites [code]KIND_X as int[/code]
## casts at every one of those boundaries and buys nothing back. The numbers are part
## of the format, so they are written down as numbers.
##
## [b]Zero is not a kind, and nothing may allocate it.[/b] GameSpice Combat already treats
## [code]entity_id == 0[/code] as "no attacker" — a fall, drowning, the world — and
## every game in the tree relies on that. Reserving it here keeps that meaning true by
## construction rather than by everybody remembering.
const KIND_NONE := 0     ## No entity. The world, a fall, an unattributed death.
const KIND_PLAYER := 1   ## A person playing. One per [code]GSPlayer[/code].
const KIND_NPC := 2      ## Something the server drives.
const KIND_VEHICLE := 3  ## Something a player rides or drives.
const KIND_PROP := 4     ## Something spawned into the world and simulated.
const KIND_PROJECTILE := 5  ## A rocket, a grenade, anything with a lifetime of its own.
const KIND_OBJECTIVE := 6   ## A bomb, a cart, a flag — a thing a round is about.
const KIND_TRIGGER := 7     ## A volume that reports rather than collides.
const KIND_OTHER := 8    ## A game's own kind. Nothing here interprets it.

## The highest built-in kind: the default of [member kind_limit]. See [constant STRIDE].
const KIND_MAX := 8

## The highest kind the id layout can hold at all, whatever [member kind_limit] says: the
## largest kind for which [code]kind * STRIDE + SERIAL_MAX[/code] still fits an [code]int64[/code].
const KIND_FORMAT_MAX := 9_223_371

## The highest kind in use, and a setting: [code]0[/code] means [constant KIND_FORMAT_MAX].
##
## [b]Default 8, the built-in kinds.[/b] A game that wants kinds of its own raises it
## with [method set_kind_limit] once at startup, names them with [method register_kind],
## and the ids stay byte-for-byte compatible: the stride and the meaning of kinds 1..8
## do not change. [method set_kind_limit] refuses a value the format cannot hold rather
## than clamping it.
static var kind_limit: int = KIND_MAX

## Names for kinds above [constant KIND_MAX], registered by the game.
static var _extra_names: Dictionary = {}

## Short names, for logs and for [method describe_id].
##
## Indexed by kind, so the lookup is an array index rather than a match statement that
## every new kind has to be added to in two places.
const KIND_NAMES: Array[StringName] = [
	&"none",
	&"player",
	&"npc",
	&"vehicle",
	&"prop",
	&"projectile",
	&"objective",
	&"trigger",
	&"other",
]

## How many serials each kind gets: [code]id = kind * STRIDE + serial[/code].
##
## [b]A decimal power of ten rather than a bit shift, and the size is a real
## trade-off.[/b] These numbers are read by humans far more often than they are
## decoded by machines — they appear in kill feeds, in `describe()` dumps, in server
## logs and in bug reports — and with a decimal stride a reader can see the kind
## without doing anything: [code]2000000000041[/code] is the forty-first NPC. A bit
## layout would be marginally faster to decode and unreadable everywhere it is
## actually looked at.
##
## A trillion serials per kind is 31 years at a thousand spawns a second, and
## the default eight kinds fit inside an [code]int64[/code] with four orders of
## magnitude to spare ([constant KIND_FORMAT_MAX] is the hard ceiling). Exhaustion is still handled rather than assumed: see
## [method GSEntityTable.open].
const STRIDE := 1_000_000_000_000

## The largest serial a kind can hold. The format ceiling; a table can set a lower
## limit with [member GSEntityTable.serial_limit], never a higher one.
const SERIAL_MAX := STRIDE - 1


## Sets [member kind_limit]. [code]0[/code] means [constant KIND_FORMAT_MAX]. Fails with
## [constant GSError.CODE_INVALID], and changes nothing, for a negative value, one below
## [constant KIND_MAX] (a built-in kind would become unusable) or one the layout cannot hold.
static func set_kind_limit(limit: int) -> GSResult:
	if limit == 0:
		kind_limit = KIND_FORMAT_MAX
		return GSResult.success(kind_limit)

	if limit < KIND_MAX or limit > KIND_FORMAT_MAX:
		return GSResult.fail(
			GSError.CODE_INVALID,
			"The kind limit must be 0 (unlimited) or between %d and %d." % [KIND_MAX, KIND_FORMAT_MAX],
			"limit=%d" % limit
		)

	kind_limit = limit

	return GSResult.success(kind_limit)


## Names a kind above [constant KIND_MAX] for logs and [method describe_id]. Fails with
## [constant GSError.CODE_INVALID] for a built-in kind, a kind beyond [member kind_limit]
## or an empty name.
static func register_kind(kind: int, kind_name: StringName) -> GSResult:
	if kind <= KIND_MAX or kind > kind_limit or kind_name == &"":
		return GSResult.fail(
			GSError.CODE_INVALID,
			"A registered kind must be above %d, within the kind limit, and named." % KIND_MAX,
			"kind=%d limit=%d" % [kind, kind_limit]
		)

	_extra_names[kind] = kind_name

	return GSResult.success(kind)


## The id for a kind and a serial. The only place the layout is spelled out.
static func make_id(kind: int, serial: int) -> int:
	if kind <= KIND_NONE or kind > kind_limit or serial <= 0 or serial > SERIAL_MAX:
		return 0

	return kind * STRIDE + serial


## What sort of thing this id names, or [constant KIND_NONE].
##
## Total, on purpose: a negative id, a zero and an id from a kind this build does not
## know about all answer [constant KIND_NONE] rather than producing a number that
## indexes off the end of [constant KIND_NAMES].
static func kind_of(id: int) -> int:
	if id <= 0:
		return KIND_NONE

	@warning_ignore("integer_division")
	var kind := id / STRIDE

	return kind if kind <= kind_limit else KIND_NONE


## The serial within its kind. Unique for the life of one [GSEntityTable].
static func serial_of(id: int) -> int:
	return (id % STRIDE) if id > 0 else 0


## Whether this id names a [param kind].
##
## The replacement for every game's hand-written range check.
static func is_kind(id: int, kind: int) -> bool:
	return kind_of(id) == kind


## Whether this id names anything at all.
##
## [b]Not the same question as whether the entity is still alive[/b], which only
## [method GSEntityTable.is_open] can answer. This one is about the number.
static func is_valid(id: int) -> bool:
	return kind_of(id) != KIND_NONE


## The short name of a kind: [code]"npc"[/code].
static func kind_name(kind: int) -> StringName:
	if kind >= 0 and kind < KIND_NAMES.size():
		return KIND_NAMES[kind]

	if kind > KIND_MAX and kind <= kind_limit:
		return _extra_names.get(kind, StringName("kind%d" % kind))

	return &"?"


## An id as a person reads it: [code]"npc#41"[/code].
##
## For logs, kill feeds and [code]describe()[/code] output. Never parsed back — the id
## itself is what travels, and a second spelling of one serialisation is a thing this
## family has now paid for twice.
static func describe_id(id: int) -> String:
	if id == 0:
		return "none"

	if not is_valid(id):
		return "bad#%d" % id

	return "%s#%d" % [kind_name(kind_of(id)), serial_of(id)]
