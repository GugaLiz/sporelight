extends SceneTree
const Normalizer = preload("res://services/snapshot_normalizer.gd")
const Factory = preload("res://core/world_factory.gd")
const Repository = preload("res://services/save_repository.gd")
var checks := 0
var failures: Array[String] = []

class CountedNormalizer:
	extends Normalizer
	var calls := 0
	func _normalize_uncached(id: String, value: Dictionary) -> Dictionary:
		calls += 1
		return super._normalize_uncached(id, value)

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _run() -> void:
	_test_numeric_boundaries()
	var cache := CountedNormalizer.new()
	for id: String in Repository.LEVEL_IDS:
		var world: RefCounted = Factory.create(id)
		var initial: Dictionary = world.snapshot()
		var expected: Dictionary = world.normalize_saved(initial)
		var first: Dictionary = cache.normalize(initial)
		check(Repository.json_equivalent(first, expected), id + " first normalization matches domain")
		var calls: int = cache.calls
		var again: Dictionary = cache.normalize(initial)
		check(cache.calls == calls and Repository.json_equivalent(again, expected), id + " equal values reuse validation")
		var json_value: Dictionary = JSON.parse_string(JSON.stringify(initial, "", true, true))
		check(Repository.json_equivalent(cache.normalize(json_value), expected) and cache.calls == calls, id + " disk numeric roundtrip uses same verified result")
		first.snapshot.actors.luvie = "invalid-return-mutation"
		again.snapshot.flags.append("invalid-return-mutation")
		check(Repository.json_equivalent(cache.normalize(initial), expected), id + " callers cannot corrupt cached result")
		initial.actors.luvie = "invalid-input-mutation"
		check(not cache.normalize(initial).ok and cache.calls == calls + 1, id + " changed nested actor must be checked and rejected")
		check(not cache.normalize(initial).ok and cache.calls == calls + 2, id + " failures are never cached")
		check(Repository.json_equivalent(cache.normalize(world.snapshot()), expected), id + " input mutation cannot corrupt cache key")
		var forged: Dictionary = world.snapshot()
		forged.completed = 0
		var direct: Dictionary = world.normalize_saved(forged)
		calls = cache.calls
		check(Repository.json_equivalent(cache.normalize(forged), direct) and cache.calls == calls + 1, id + " bool and number never share a cache entry")
		for malformed: Dictionary in [{"designVersion": 99}, {"runtime": {"version": 1, "poses": {"luvie": {"support": world.state.actors.luvie, "x": INF}}}}, {"actors": null}]:
			var bad: Dictionary = world.snapshot()
			bad.merge(malformed, true)
			calls = cache.calls
			check(Repository.json_equivalent(cache.normalize(bad), world.normalize_saved(bad)) and cache.calls == calls + 1, id + " changed version/runtime/schema goes through real validator")
		# Valid changing observations produce distinct values; the small bound
		# also holds if a domain normalizer discards unknown observation names.
		for index in range(8):
			var varied: Dictionary = world.snapshot()
			varied["cache_probe"] = index
			check(Repository.json_equivalent(cache.normalize(varied), world.normalize_saved(varied)), id + " alternate input matches original validator")
		check(cache._entries[id].size() <= Normalizer.ENTRIES_PER_LEVEL, id + " bounded per-level storage")
	cache.clear()
	check(cache._entries.is_empty(), "explicit invalidation releases all snapshots")
	check(not cache.normalize({"levelId": "unknown"}).ok, "unknown level cannot reuse fallback world")
	# Compare many non-initial authored states as well as canonical disk copies.
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	var authored_checks := 0
	for entry: Dictionary in fixture.get("cases", []):
		var id := str(entry.get("levelId", ""))
		if id == "1-1" or not id in Repository.LEVEL_IDS: continue
		for step: Dictionary in entry.get("steps", []):
			var snapshot: Dictionary = step.get("snapshot", {})
			if snapshot.is_empty(): continue
			var expected: Dictionary = Factory.create(id).normalize_saved(snapshot)
			check(Repository.json_equivalent(cache.normalize(snapshot), expected), id + " authored state agrees")
			authored_checks += 1
	check(authored_checks > 100, "non-initial fixture coverage actually executed")
	print(JSON.stringify({"suite": "snapshot-normalizer", "passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _test_numeric_boundaries() -> void:
	var limit: int = 9007199254740991
	var maximum: int = 9223372036854775807
	for integer: int in [limit - 1, limit, limit + 1, limit + 2, limit + 3, -limit + 1, -limit, -limit - 1, -limit - 2, -limit - 3, maximum, maximum - 1, -maximum]:
		var native := {"nested": [{"number": integer}]}
		var same := {"nested": [{"number": integer}]}
		var mixed := {"nested": [{"number": float(integer)}]}
		var safe := integer >= -limit and integer <= limit
		check(Normalizer._cache_equivalent(native, same), "identical int64 remains exact: " + str(integer))
		check(Normalizer._cache_equivalent(native, mixed) == safe and Normalizer._cache_equivalent(mixed, native) == safe, "mixed numeric boundary is conservative in both directions: " + str(integer))
		var adjacent: int = integer - 1 if integer == maximum else integer + 1
		check(not Normalizer._cache_equivalent(native, {"nested": [{"number": adjacent}]}), "adjacent int64 values never merge: " + str(integer))
	check(not Normalizer._cache_equivalent({"a": [true, false]}, {"a": [1, 0]}), "nested bool never equals integer")
	check(not Normalizer._cache_equivalent({"a": [1.0, 0.0]}, {"a": [true, false]}), "nested float never equals bool")
	check(not Normalizer._cache_equivalent({"a": null}, {}), "missing key stays distinct from null")
	check(not Normalizer._cache_equivalent([1, 2], [2.0, 1.0]), "array ordering stays exact")
	check(Normalizer._cache_equivalent({"a": [1, 2]}, {"a": [1.0, 2.0]}), "safe nested JSON numeric roundtrip still hits")
	# Real domain counterexample: adjacent large turns normalize to different
	# quarter-turns even when float(int64) would collapse the cache keys.
	var world: RefCounted = Factory.create("1-3")
	for first_turn: int in [limit + 1, -limit - 2, maximum - 1]:
		var cache := CountedNormalizer.new()
		var first: Dictionary = world.snapshot()
		first.turns.garden = first_turn
		var second: Dictionary = world.snapshot()
		second.turns.garden = first_turn + 1
		var a: Dictionary = cache.normalize(first)
		var b: Dictionary = cache.normalize(second)
		check(a.ok and b.ok and int(a.snapshot.turns.garden) == posmod(first_turn, 4) and int(b.snapshot.turns.garden) == posmod(first_turn + 1, 4), "large-turn normalization preserves actual modulo: " + str(first_turn))
		check(cache.calls == 2, "distinct large turns both invoke the real domain validator")
		cache.normalize(second)
		check(cache.calls == 2, "identical large native turn can still reuse its own verified result")
		var numeric_probe: Dictionary = world.snapshot()
		numeric_probe.cache_probe = {"nested": [first_turn]}
		cache.normalize(numeric_probe)
		var calls := cache.calls
		numeric_probe.cache_probe.nested[0] = float(first_turn)
		cache.normalize(numeric_probe)
		check(cache.calls == calls + 1, "unsafe nested int/float invokes validator instead of cache")
