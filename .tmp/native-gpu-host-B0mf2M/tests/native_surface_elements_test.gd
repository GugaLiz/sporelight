extends SceneTree
const Surfaces = preload("res://elements/surface_definitions.gd")
const Chapter = preload("res://presentation/native/chapter_surface_materials.gd")
const First = preload("res://presentation/native/first_garden_profile.gd")
const Second = preload("res://presentation/native/second_garden_profile.gd")
var checks := 0
var failures: Array[String] = []
var textures := {}
func _initialize() -> void: _run.call_deferred()
func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func _texture(alias: String) -> Texture2D:
	if not textures.has(alias):
		var img := Image.create(2,2,false,Image.FORMAT_RGBA8)
		var tex := ImageTexture.create_from_image(img)
		tex.set_meta("alias",alias)
		textures[alias] = tex
	return textures[alias]
func _solid(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
func _alias(texture: Texture2D) -> String: return str(texture.get_meta("alias",""))
func _run() -> void:
	Surfaces.reset()
	var tile := {"id":"f:0:1","x":0,"z":1,"h":0,"kind":"fixed"}
	var level := {"id":"1-3","chapter":"valley","marks":[{"tile":"f:0:1","kind":"pot"}]}
	var original := Chapter.create("valley",_texture,_solid)
	var revision := Surfaces.revision()
	_check(Surfaces.set_theme_overrides("valley",{"stone":"paving-pond","terrainTop":"paving-pond"}),"floor overrides accepted")
	_check(Surfaces.revision()>revision,"revision invalidates stage caches")
	var floor := Chapter.create("valley",_texture,_solid)
	_check(_alias(floor.top.albedo_texture)=="paving-pond","chapter floor replaced")
	_check(Chapter.paving_for(level,tile)=="paving-pond","per-tile floor replaced")
	_check(First.material_spec(tile).paving=="paving-pond" and Second.material_spec(tile).paving=="paving-pond","authored first/second use same floor slot")
	_check(floor.side.get_shader_parameter("wall_art")==original.side.get_shader_parameter("wall_art"),"floor replacement preserves wallpaper")
	_check(floor.ramp.get_shader_parameter("original_stair")==original.ramp.get_shader_parameter("original_stair"),"floor replacement preserves stair paint")
	_check(Surfaces.set_theme_overrides("valley",{"wallLeft":"wall-left","wallRight":"wall-right"}),"wall overrides accepted")
	var walls := Chapter.create("valley",_texture,_solid)
	_check(walls.top.albedo_texture==original.top.albedo_texture,"wall replacement preserves floor")
	_check(_alias(walls.side.get_shader_parameter("wall_art"))=="wall-left" and _alias(walls.side.get_shader_parameter("wall_art_right"))=="wall-right","both wall faces replace independently")
	_check(walls.ramp.get_shader_parameter("original_stair")==original.ramp.get_shader_parameter("original_stair"),"wall replacement preserves stair paint")
	_check(Chapter.paving_for({"id":"2-1","chapter":"pond","marks":level.marks},tile)=="paving-pond","chapter override isolated")
	var copy := Surfaces.definitions()
	copy.themes.valley.wallLeft = "mutated-copy"
	_check(Surfaces.theme("valley").wallLeft=="wall-left","editor catalog copy cannot mutate runtime")
	var before := Surfaces.revision()
	for invalid: Dictionary in [{"unknown":"x"},{"wallWash":"invalid"},{"wallPixelsPerUnit":[0,2]},{"wallPixelsPerUnit":["x",2]},{"stone":""},{"stone":"unknown-texture"}]:
		_check(not Surfaces.set_theme_overrides("valley",invalid),"invalid override rejected: "+str(invalid))
	_check(not Surfaces.set_theme_overrides("unknown",{"stone":"x"}) and Surfaces.revision()==before,"rejected edits do not invalidate or mutate")
	_check(Surfaces.theme("valley").wallLeft=="wall-left","rejection is atomic")
	_check(Surfaces.set_theme_overrides("valley",{"stairPaint":"paving-grass","stairGrain":"paving-moss"}),"stair override accepted")
	var stairs := Chapter.create("valley",_texture,_solid,true)
	_check(_alias(stairs.ramp.get_shader_parameter("original_stair"))=="paving-grass" and _alias(stairs.riser.get_shader_parameter("original_stair"))=="paving-grass","riser and tread share same replacement")
	_check(stairs.ramp.get_shader_parameter("connector")==true,"stair replacement retains connector geometry flag")
	_check(_alias(stairs.top.albedo_texture)=="paving-valley","stair replacement preserves floor")
	var cloud := Chapter.create("cloud",_texture,_solid)
	_check(cloud.key=="original_cloud_cream" and cloud.side is StandardMaterial3D,"cloud special appearance preserved")
	_check(Surfaces.root_style("root").color==Color("bfcc9b"),"root palette preserved")
	_check(Surfaces.root_style("shadow",0,false).color==Color("dacb8c"),"sun palette preserved")
	_check(Surfaces.root_style("shadow",1,false).color==Color("aebcd6"),"moon palette preserved")
	_check(Surfaces.root_style("shadow",1,true).color==Color("aebcd6").lightened(.18),"memory lightening preserved")
	_check(Surfaces.root_style("shadow",1,true).emission_enabled and not Surfaces.root_style("shadow",1,false).emission_enabled,"memory emission remains state-derived")
	Surfaces.reset()
	_check(Surfaces.theme("valley").wallLeft=="masonry-valley","reset restores authored theme")
	print(JSON.stringify({"suite":"surface-elements","checks":checks,"passed":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
