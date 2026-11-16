extends SceneTree
## Run with --headless. Default is validation only; --write updates the two
## generated documentation artifacts. No game/source/save files are rewritten.
const Catalog = preload("res://elements/element_catalog.gd")
const Document = preload("res://elements/element_document.gd")
const Stage = preload("res://presentation/native/native_garden_stage.gd")
const World = preload("res://core/garden_world.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func _run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	stage.set_process(false)
	var documents: Array = []
	var summary: Array = []
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
	for id: String in Catalog.level_ids():
		var world := World.new(id)
		var initial: Dictionary = world.snapshot()
		stage.set_world(world)
		await process_frame
		var document := Catalog.for_world(world)
		Catalog.capture_scenery(document,stage)
		Catalog.capture_authored_routes(document,fixtures)
		_check(world.snapshot()==initial,id+" inspection preserves world state")
		var result := Document.decode(Document.encode(document))
		_check(result.ok and result.get("level")==world.level,id+" full document roundtrip: "+str(result.get("error","")))
		_check(int(document.scenery_observation.sprite_count)>0,id+" actual scenery captured")
		var captured := Document.encode(document)
		Catalog.capture_scenery(document,stage)
		Catalog.capture_authored_routes(document,fixtures)
		_check(Document.encode(document)==captured,id+" scenery observation IDs repeat deterministically")
		var counts := {}
		var semantics := {}
		for instance: Dictionary in document.instances:
			counts[instance.category] = int(counts.get(instance.category,0))+1
			semantics[instance.element_id] = int(semantics.get(instance.element_id,0))+1
		documents.append(document)
		summary.append({"level":id,"title":world.level.title,"counts":counts,"elements":semantics,"deferred_scenery":document.scenery_observation.deferred.size()})
		print("Inspected "+id+": "+str(document.instances.size())+" indexed records; "+str(document.scenery_observation.sprite_count)+" observed scenery sprites")
	stage.queue_free()
	await process_frame
	if "--write" in OS.get_cmdline_user_args() and failures.is_empty():
		var inventory := {"schema_version":1,"scope":"1-1 through 3-4, authored definitions and cold-start native scenery","definitions":Catalog.definitions(),"summary":summary,"levels":documents,"validation":{"checks":checks,"failures":failures}}
		FileAccess.open("res://../docs/element-library/inventory.json",FileAccess.WRITE).store_string(JSON.stringify(inventory,"  ",true)+"\n")
		var lines: Array[String] = ["# 12 关元素清单（生成文件）","","由 `godot/tests/export_element_inventory.gd --write` 读取现行关卡和真实原生舞台生成；不是人工估数。详细实例、状态绑定、原始关卡 payload 和全域定义见 `inventory.json`。","","| 关卡 | 固定地表 | 机关标记 | 移动模块 | 根路锚点 | 搬运物 | 收集物 | 装饰实际精灵 | 延迟装饰 |","|---|---:|---:|---:|---:|---:|---:|---:|---:|"]
		for row: Dictionary in summary:
			var c: Dictionary = row.counts
			lines.append("| %s %s | %d | %d | %d | %d | %d | %d | %d | %d |"%[row.level,row.title,c.get("terrain",0),c.get("mark",0),c.get("module",0),c.get("root",0),c.get("carry",0),c.get("collectible",0),c.get("scenery-observed",0),row.deferred_scenery])
		lines.append("\n每关都包含露薇与小苔灵两个角色定义。装饰精灵数是初始状态实际节点，不是浏览器旧版 SOURCE_PROPS 条目数；程序化装配、特效和变化状态由对应 adapter 记录，不把每个网格零件当成独立游戏元素。")
		for row: Dictionary in summary:
			lines.append("\n## "+str(row.level)+" "+str(row.title)+"\n")
			var keys: Array = row.elements.keys()
			keys.sort()
			for key: String in keys: lines.append("- `"+key+"` × "+str(row.elements[key]))
		lines.append("\n导出时完成 %d 项只读性、JSON 往返、装饰观察与稳定 ID 检查。此清单不等于 GPU 视觉验收。"%checks)
		FileAccess.open("res://../docs/element-library/inventory.md",FileAccess.WRITE).store_string("\n".join(lines)+"\n")
	print(JSON.stringify({"suite":"element-inventory-export","checks":checks,"failures":failures,"passed":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
