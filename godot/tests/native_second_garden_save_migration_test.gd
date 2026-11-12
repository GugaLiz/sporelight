extends SceneTree

const World = preload("res://core/garden_world.gd")
const Normalizer = preload("res://services/snapshot_normalizer.gd")
const Repository = preload("res://services/save_repository.gd")
const ROUTES := [
	["g:root:1:0", "g:root:2:0", "g:root:3:0", "g:root:3:1"],
	["g:root:1:2", "g:root:2:2", "g:root:3:2", "g:root:3:1"],
]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _legacy(route: Array, length: int, support: String = "f:3:1") -> Dictionary:
	var saved: Dictionary = World.new("1-2").snapshot()
	saved.erase("layoutRevision")
	saved.growth.root = route.slice(0, length)
	saved.actors = {"luvie": support, "buddy": "f:1:1"}
	saved.collected = ["spore-0", "spore-2"]
	saved.observations = ["observe", "rest"]
	saved.completed = length == 4
	saved.runtime = {"version": 1, "poses": {
		"luvie": {"support": support, "offset": [0.18, 0.02, -0.11], "facing": "left"},
		"buddy": {"support": "f:1:1", "offset": [-0.23, 0.0, 0.20], "facing": "front"},
	}}
	return saved

func _run() -> void:
	var world := World.new("1-2")
	_check(world.state.layoutRevision == 2, "new second garden starts with the corrected layout revision")
	_check(world.point_for("f:3:1").is_empty() and world.point_for("f:4:2").is_empty(), "test uses the actual corrected board, not fabricated replacement supports")
	var cache := Normalizer.new()
	for route: Array in ROUTES:
		for length in range(5):
			for support: String in ["f:3:1", "f:4:2", "f:4:1", "f:5:0", "f:5:2"]:
				var old := _legacy(route, length, support)
				var before := old.duplicate(true)
				var result := world.normalize_saved(old)
				var label := str([route[0], length, support])
				_check(result.ok, label + " valid legacy save migrates")
				_check(old == before, label + " input snapshot is not mutated")
				if not result.ok: continue
				var restored: Dictionary = result.snapshot
				var expected := (str(route[length - 1]) if length > 0 else "f:1:1") if length < 4 else "g:root:3:1" if support == "f:3:1" else "f:5:2" if support == "f:4:2" else support
				_check(restored.actors.luvie == expected and restored.actors.buddy == "f:1:1", label + " only affected actor relocates to a real support")
				for field: String in ["growth", "collected", "observations", "completed", "flags", "follow", "active"]:
					_check(restored[field] == before[field], label + " preserves " + field)
				_check(restored.runtime.poses.buddy == before.runtime.poses.buddy, label + " untouched actor retains its exact stance")
				if length == 4 and support != "f:4:2":
					_check(restored.runtime.poses.luvie.offset == before.runtime.poses.luvie.offset and restored.runtime.poses.luvie.support == expected, label + " same-position alias preserves offset and updates support")
				else:
					_check(not restored.runtime.poses.has("luvie"), label + " relocated actor discards obsolete pose after validation")
				_check(restored.layoutRevision == 2, label + " migration is stamped")
				_check(world.normalize_saved(restored).snapshot == restored, label + " migration is idempotent")
				_check(World.new("1-2", old).snapshot() == restored, label + " direct construction and explicit normalization agree")
				var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(old))
				_check(Repository.json_equivalent(cache.normalize(roundtrip), result), label + " JSON and cached normalization preserve migration")
	_test_rejections(world)
	_test_untouched(world)
	_test_file_roundtrip()
	_check(not World.new("1-1").snapshot().has("layoutRevision"), "first garden save schema is unaffected")
	print(JSON.stringify({"suite": "native-second-garden-save-migration", "passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _reject(world: RefCounted, saved: Dictionary, label: String) -> void:
	var before := saved.duplicate(true)
	_check(not world.normalize_saved(saved).ok, label)
	# NaN does not compare equal to itself; the ordinary cases still prove
	# rejection cannot mutate the caller's saved actor or root path.
	_check(saved.actors == before.actors and saved.growth == before.growth, label + " leaves source positions and path untouched")

func _test_rejections(world: RefCounted) -> void:
	for path: Array in [["g:root:2:0"], ["g:other:1:0"], ["g:root:2:1"], ["g:root:1:0", "g:root:1:0"], ["g:root:1:0", 42], ROUTES[0] + ["g:root:3:2"]]:
		var saved := _legacy(ROUTES[0], 3)
		saved.growth.root = path
		_reject(world, saved, "invalid old root chain rejected before migration: " + str(path))
	for revision: Variant in [0, 3, true, "1", 1.5]:
		var saved := _legacy(ROUTES[0], 3)
		saved.layoutRevision = revision
		_reject(world, saved, "unsupported or noninteger layout revision rejected: " + str(revision))
	for support: String in ["f:3:1", "f:4:2", "f:99:1"]:
		var saved := _legacy(ROUTES[0], 4, support)
		saved.layoutRevision = 2
		_reject(world, saved, "current revision cannot use removed or unknown support: " + support)
	var unknown := _legacy(ROUTES[0], 3, "f:99:1")
	_reject(world, unknown, "legacy relocation does not excuse a nonexistent original support")
	var mismatch := _legacy(ROUTES[0], 3)
	mismatch.runtime.poses.luvie.support = "f:4:1"
	_reject(world, mismatch, "obsolete pose must name original actor support before migration")
	for offset: Array in [[0.76, 0, 0], [0, NAN, 0], [true, 0, 0], [0, 0], ["0", 0, 0]]:
		var saved := _legacy(ROUTES[0], 3)
		saved.runtime.poses.luvie.offset = offset
		_reject(world, saved, "invalid old pose cannot be silently erased by relocation: " + str(offset))
	for version: Variant in [1.2, "1", true, {}]:
		var saved := _legacy(ROUTES[0], 3)
		saved.runtime.version = version
		_reject(world, saved, "runtime version is validated before relocation: " + str(version))
	var poses := _legacy(ROUTES[0], 3)
	poses.runtime.poses = []
	_reject(world, poses, "malformed pose container rejected")
	var stranger := _legacy(ROUTES[0], 3)
	stranger.runtime.poses.intruder = stranger.runtime.poses.luvie.duplicate(true)
	_reject(world, stranger, "unknown pose actor rejected")

func _test_untouched(world: RefCounted) -> void:
	var old := _legacy(ROUTES[1], 3, "g:root:3:2")
	var result: Dictionary = world.normalize_saved(old)
	_check(result.ok and result.snapshot.actors == old.actors and result.snapshot.runtime == old.runtime, "actor already on the third root keeps its valid stance")
	var explicit := _legacy(ROUTES[0], 4)
	explicit.layoutRevision = 1
	var expected: Dictionary = world.normalize_saved(explicit)
	_check(expected.ok and expected.snapshot.actors.luvie == "g:root:3:1", "explicit revision 1 receives the same migration")
	var without_pose := _legacy(ROUTES[0], 3)
	without_pose.erase("runtime")
	_check(world.normalize_saved(without_pose).ok, "legacy browser save without native poses remains supported")
	var pair := _legacy(ROUTES[0], 4)
	pair.actors.buddy = "f:4:2"
	pair.runtime.poses.buddy.support = "f:4:2"
	var migrated: Dictionary = world.normalize_saved(pair)
	_check(migrated.ok and migrated.snapshot.actors == {"luvie": "g:root:3:1", "buddy": "f:5:2"}, "two removed supports migrate independently in one snapshot")
	if migrated.ok:
		_check(migrated.snapshot.runtime.poses.has("luvie") and not migrated.snapshot.runtime.poses.has("buddy"), "same-position actor retains pose while relocated companion drops only its own pose")

func _test_file_roundtrip() -> void:
	var path := "user://tests/second-garden-migration-%d.json" % Time.get_ticks_usec()
	var repository := Repository.new(path)
	var cache := Normalizer.new()
	repository.snapshot_validator = cache.normalize
	_check(repository.load_store().ok, "isolated repository initializes")
	var old := _legacy(ROUTES[1], 4)
	_check(repository.commit_run(old).ok, "real repository accepts and normalizes old complete save")
	var reloaded := Repository.new(path)
	var reload_normalizer := Normalizer.new()
	reloaded.snapshot_validator = reload_normalizer.normalize
	var result := reloaded.load_store()
	_check(result.ok, "migrated save survives actual disk validation")
	if result.ok and reloaded.data.mainline.runs.has("1-2"):
		var run: Dictionary = reloaded.data.mainline.runs["1-2"]
		_check(run.layoutRevision == 2 and run.actors.luvie == "g:root:3:1", "disk persists canonical revision and support")
		_check(run.completed and run.growth.root == ROUTES[1] and run.collected == old.collected and run.observations == old.observations, "disk preserves completion and earned progress")
	# Also load bytes produced by the previous layout, rather than testing
	# only commits that already normalized the snapshot before writing it.
	var legacy_store: Dictionary = Repository.empty_store()
	legacy_store.mainline.last_level = "1-2"
	legacy_store.mainline.runs["1-2"] = old.duplicate(true)
	legacy_store.mainline.memories["1-2"] = old.duplicate(true)
	legacy_store.mainline.records["1-2"] = {"completed": true, "collected": 2, "stars": 2}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy_store, "", true, true))
	file.close()
	var imported := Repository.new(path)
	var import_normalizer := Normalizer.new()
	imported.snapshot_validator = import_normalizer.normalize
	var loaded := imported.load_store()
	_check(loaded.ok, "actual legacy file loads through repository validation")
	if loaded.ok:
		for section: String in ["runs", "memories"]:
			var snapshot: Dictionary = imported.data.mainline[section]["1-2"]
			_check(snapshot.get("layoutRevision") == 2 and snapshot.actors.luvie == "g:root:3:1" and snapshot.completed, "legacy file migrates " + section + " without losing completion")
		_check(Repository.json_equivalent(imported.data.mainline.records["1-2"], legacy_store.mainline.records["1-2"]), "legacy completion statistics remain untouched")
		_check(imported.persist().ok, "migrated legacy store passes strict canonical write-back verification")
	for suffix: String in ["", ".bak", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
