extends RefCounted
## Click original visible art, then route to its unchanged interaction support.
## Static source alpha is cached; no rectangle-sized invisible click target.
static var _source_images: Dictionary = {}
static var _mesh_faces: Dictionary = {}
static func core_support(stage: Node, screen: Vector2) -> String:
	if str(stage.world.level.id) == "1-1": return ""
	var selected := ""
	var nearest := INF
	var origin: Vector3 = stage._camera.project_ray_origin(screen)
	var direction: Vector3 = stage._camera.project_ray_normal(screen)
	for mark: Dictionary in stage.world.level.get("marks",[]):
		if str(mark.get("kind","")) != "core": continue
		var support := str(mark.get("tile",""))
		var tile: Dictionary = stage._tile_map.get(support,{})
		if tile.is_empty() or bool(tile.get("solid",false)) or not stage.world.visible(tile): continue
		var root: Node3D = stage._props_nodes.get("mark:"+str(mark.id))
		if root == null or not root.is_visible_in_tree(): continue
		for child in root.get_children():
			if not child is Sprite3D or not child.has_meta("core_planter") or child.texture == null or not child.is_visible_in_tree(): continue
			var card := child as Sprite3D
			var shift: Vector3 = card.get_meta("ground_footprint_center",Vector3(0,0,.07))-Vector3(0,0,.07)
			if shift.is_zero_approx(): continue
			var distance := _opaque_distance(card,stage._camera,origin,direction)
			if distance<=0 or distance>=nearest: continue
			var point := origin+direction*distance
			# A nearer terrain face must still occlude an object click.
			var query := PhysicsRayQueryParameters3D.create(origin,point,1)
			var hit: Dictionary = stage._scene.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and origin.distance_to(hit.position)<distance-.02: continue
			if _art_occludes(stage,card,origin,direction,distance): continue
			nearest = distance
			selected = support
	return selected

static func _opaque_distance(card: SpriteBase3D, camera: Camera3D, origin: Vector3, direction: Vector3) -> float:
	if not card.is_visible_in_tree() or card.modulate.a < .5: return INF
	var texture: Texture2D = card.texture if card is Sprite3D else card.sprite_frames.get_frame_texture(card.animation,card.frame)
	if texture == null: return INF
	# Rendered buddy/mole cards have no CPU image under the dummy renderer.
	# In the real renderer sample their current frame, never cache stale pixels.
	if texture is ViewportTexture and DisplayServer.get_name() == "headless": return INF
	var transform := card.global_transform
	if card.billboard == BaseMaterial3D.BILLBOARD_ENABLED:
		transform.basis = camera.global_basis.orthonormalized().scaled(card.global_basis.get_scale())
	var normal := transform.basis.z.normalized()
	var denominator := direction.dot(normal)
	if absf(denominator)<.00001: return INF
	var distance := (transform.origin-origin).dot(normal)/denominator
	if distance<=0: return INF
	var local := transform.affine_inverse()*(origin+direction*distance)
	var centre := Vector2(texture.get_width(),texture.get_height())*.5 if card.centered else Vector2.ZERO
	var pixel := Vector2i(floori(local.x/card.pixel_size+centre.x-card.offset.x),floori(centre.y+card.offset.y-local.y/card.pixel_size))
	if card.flip_h: pixel.x = texture.get_width()-1-pixel.x
	if card.flip_v: pixel.y = texture.get_height()-1-pixel.y
	if pixel.x<0 or pixel.y<0 or pixel.x>=texture.get_width() or pixel.y>=texture.get_height(): return INF
	var key := str(texture.resource_path)+"/"+str(texture.get_instance_id())
	if not texture is ViewportTexture and not _source_images.has(key): _source_images[key] = texture.get_image()
	var picture: Image = texture.get_image() if texture is ViewportTexture else _source_images[key]
	if picture == null: return INF
	if pixel.x<0 or pixel.y<0 or pixel.x>=picture.get_width() or pixel.y>=picture.get_height() or picture.get_pixelv(pixel).a*card.modulate.a<.5: return INF
	return distance

static func _art_occludes(stage: Node, target: Sprite3D, origin: Vector3, direction: Vector3, distance: float) -> bool:
	# Decorative props deliberately have no collision. Their actual opaque
	# source pixels still block clicks, as do character silhouettes in front.
	for group: Node in [stage._props,stage._actors]:
		for card: SpriteBase3D in group.find_children("*","SpriteBase3D",true,false):
			if card == target: continue
			if _opaque_distance(card,stage._camera,origin,direction)<distance-.02: return true
	# Opaque mesh props (wheel, arch posts, etc.) use their real triangles,
	# never their bounding rectangles or the soft contact-shadow meshes.
	for node: MeshInstance3D in stage._props.find_children("*","MeshInstance3D",true,false):
		if not node.is_visible_in_tree() or node.mesh == null: continue
		var material := node.get_active_material(0)
		if not material is BaseMaterial3D or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
		var local_from := node.to_local(origin)
		var local_to := node.to_local(origin+direction*(distance-.02))
		if not node.get_aabb().intersects_segment(local_from,local_to): continue
		var key := node.mesh.get_rid()
		if not _mesh_faces.has(key): _mesh_faces[key] = node.mesh.get_faces()
		var faces: PackedVector3Array = _mesh_faces[key]
		for index in range(0,faces.size(),3):
			if Geometry3D.segment_intersects_triangle(local_from,local_to,faces[index],faces[index+1],faces[index+2]) != null: return true
	return false
