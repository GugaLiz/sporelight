extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720,720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var art := TextureRect.new()
	art.texture = load("res://assets/images/full-asset-redraw-20261116/map-plant-bloom.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.size = Vector2(720,720)
	viewport.add_child(art)
	for n in range(0,257,8):
		var v := ColorRect.new()
		v.color = Color(0,0,1,.2)
		v.position = Vector2(n*720.0/256,0)
		v.size = Vector2(1,720)
		viewport.add_child(v)
		var h := ColorRect.new()
		h.color = Color(0,0,1,.2)
		h.position = Vector2(0,n*720.0/256)
		h.size = Vector2(720,1)
		viewport.add_child(h)
		var label := Label.new()
		label.text = str(n)
		label.position = Vector2(n*720.0/256,180)
		label.add_theme_font_size_override("font_size",10)
		viewport.add_child(label)
		var side := Label.new()
		side.text = str(n)
		side.position = Vector2(450,n*720.0/256)
		side.add_theme_font_size_override("font_size",10)
		viewport.add_child(side)
	for unused in 3: await process_frame
	for unused in 2: await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("G:/works/liuli/sporelight/docs/qa-godot-native/menu-layout-polish-20261118/source-bloom-grid.png")
	quit()

