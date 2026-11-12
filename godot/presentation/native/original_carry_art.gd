class_name OriginalCarryArt
extends RefCounted
## itemArt.ts drawCarryBag semantics: a small leaf pouch with an item thumbnail,
## not a miniature ground pedestal or a full-size reflective mechanism.
## Images are composited once on the CPU per item/cord variant, never per frame.
const CANVAS := Vector2i(64,64)
const ORIGIN := Vector2(24,48)
const RASTER := 4
const CHARACTER_PIXEL := 1.6 / 115.0
const POUCH_SCALE := .65
const BUDDY_SCALE := .66
static var _textures: Dictionary = {}
static var rasterizations := 0

static func apply(stage: Node, who: String, carry_sprite: Sprite3D, model: Node3D, item_id: String, item: Dictionary) -> void:
	# Cloud's star seed retains its dedicated, separately authored carry art.
	if item_id in ["cloudSeed","cloud-seed","seed"] and str(stage.world.level.id).begins_with("cloud-"): return
	var alias := "dew-parcel" if item_id=="dew" else "light" if item_id=="lamp" else "lilypad" if item_id.begins_with("mirror") else "crystal"
	var source: Texture2D = null if item_id=="bell" else stage._texture(alias)
	# Warm both cord variants together so a later pose change only swaps a ref.
	var with_cord := texture(item_id,source,true)
	var no_cord := texture(item_id,source,false)
	carry_sprite.set_meta("original_carry_with_cord",with_cord)
	carry_sprite.set_meta("original_carry_no_cord",no_cord)
	carry_sprite.set_meta("original_carry_id",item_id)
	carry_sprite.set_meta("original_carry_angle",int(item.get("angle",0)))
	carry_sprite.set_meta("original_carry_semantics","leaf-pouch-thumbnail")
	carry_sprite.set_meta("original_carry_source_pixels",25.0 if item_id=="dew" else 18.0)
	carry_sprite.set_meta("original_carry_pouch_scale",POUCH_SCALE)
	carry_sprite.pixel_size=CHARACTER_PIXEL/RASTER*(BUDDY_SCALE if who=="buddy" else 1.0)
	# Source (7,-18), the pouch centre, meets the existing native hand anchor.
	# Neither the sprite nor CarryModel transforms are moved or rescaled here.
	carry_sprite.offset=Vector2((CANVAS.x*.5-ORIGIN.x-7.0)*RASTER,(ORIGIN.y-18.0-CANVAS.y*.5)*RASTER)
	carry_sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	carry_sprite.no_depth_test=false
	carry_sprite.shaded=false
	carry_sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	carry_sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	carry_sprite.modulate=Color("ffe5a2") if item_id=="sunPost" else Color("bfd7ff") if item_id=="moonPost" else Color.WHITE
	carry_sprite.visible=true
	model.visible=false
	pose(carry_sprite,who,str(item.get("visualPose","idle-front")),bool(item.get("rolling",false)))

static func pose(carry_sprite: Sprite3D, who: String, pose_name: String, rolling: bool=false) -> void:
	if not carry_sprite.has_meta("original_carry_with_cord"): return
	var show_cord:=who=="buddy" or not rolling and (pose_name=="idle-front" or pose_name in ["walk-1","walk-2","walk-7","walk-8","walk-9","walk-10","walk-11","walk-12"])
	carry_sprite.texture=carry_sprite.get_meta("original_carry_with_cord" if show_cord else "original_carry_no_cord")
	carry_sprite.set_meta("original_carry_cord_visible",show_cord)

static func texture(item_id: String, source: Texture2D, show_cord: bool) -> Texture2D:
	var source_key:=source.resource_path if source!=null and not source.resource_path.is_empty() else str(source.get_instance_id() if source else 0)
	var key:=item_id+":"+source_key+":"+str(show_cord)
	if _textures.has(key): return _textures[key]
	var cord:=""
	if show_cord: cord='<path d="M0 -31 C1 -28 4 -26 7 -23" stroke="#7c8862" stroke-width="1.6" stroke-linecap="round" fill="none"/><path d="M-.3 -31 C.7 -28 3.7 -26 6.7 -23" stroke="#bdc69a" stroke-width=".5" fill="none"/>'
	var pouch:=""
	if item_id!="dew": pouch='<g transform="translate(7 -18) scale(.65) translate(-12 20)"><ellipse cx="12" cy="-18" rx="12" ry="10" fill="url(#leaf)"/><ellipse cx="12" cy="-26" rx="10" ry="3.7" fill="#576746"/></g>'
	var result:=_svg(cord+pouch)
	if source!=null:
		var thumb:=source.get_image()
		if thumb!=null:
			if thumb.is_compressed(): thumb.decompress()
			thumb.convert(Image.FORMAT_RGBA8)
			var source_width:=25.0 if item_id=="dew" else 18.0
			var width:=source_width*POUCH_SCALE
			var height:=width*float(thumb.get_height())/float(thumb.get_width())
			var anchor:=1.0 if item_id=="dew" else .72
			var bottom:=-18.0+POUCH_SCALE*(12.0 if item_id=="dew" else 0.0)
			thumb.resize(maxi(1,roundi(width*RASTER)),maxi(1,roundi(height*RASTER)),Image.INTERPOLATE_LANCZOS)
			var at:=Vector2i(roundi((ORIGIN.x+7.0-width*.5)*RASTER),roundi((ORIGIN.y+bottom-height*anchor)*RASTER))
			result.blend_rect(thumb,Rect2i(Vector2i.ZERO,thumb.get_size()),at)
	var detail:=""
	if item_id=="bell": detail='<g transform="translate(7 -18) scale(.65) translate(-12 20) translate(12 -17) scale(.45)"><path d="M-5 -35 A5 5 0 0 1 5 -35" stroke="#ab8751" stroke-width="3" fill="none"/><path d="M-14 -7 Q-8 -14 -9 -25 Q0 -39 9 -25 Q8 -14 14 -7 Z" fill="url(#gold)" stroke="#ab8751" stroke-width="3"/><ellipse cx="0" cy="-7" rx="14" ry="4" fill="#9b743e"/><ellipse cx="0" cy="-5" rx="4" ry="4" fill="#efd49b"/></g>'
	if item_id!="dew": detail+='<g transform="translate(7 -18) scale(.65) translate(-12 20)"><path d="M5 -12 Q-3 -16 2 -22 Q11 -20 5 -12 M17 -11 Q13 -19 23 -21 Q28 -13 17 -11" fill="#a8be7c" stroke="#718451" stroke-width=".65"/><path d="M5 -10 Q12 -6 20 -14" fill="none" stroke="#d3d5a1" stroke-opacity=".49" stroke-width=".7"/></g>'
	if show_cord: detail+='<ellipse cx="6" cy="-23" rx="1.1" ry=".8" transform="rotate(-34.4 6 -23)" fill="#b8bd87"/>'
	var overlay:=_svg(detail)
	result.blend_rect(overlay,Rect2i(Vector2i.ZERO,overlay.get_size()),Vector2i.ZERO)
	result.generate_mipmaps()
	var output:=ImageTexture.create_from_image(result)
	_textures[key]=output
	rasterizations+=1
	return output

static func _svg(contents: String) -> Image:
	var image:=Image.new()
	var svg:='<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="-24 -48 64 64"><defs><radialGradient id="leaf" cx="33%" cy="30%"><stop stop-color="#d0d598"/><stop offset=".55" stop-color="#91a364"/><stop offset="1" stop-color="#596d48"/></radialGradient><linearGradient id="gold" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#fff0b0"/><stop offset=".5" stop-color="#deb56a"/><stop offset="1" stop-color="#a87b41"/></linearGradient></defs>'+contents+'</svg>'
	var error:=image.load_svg_from_string(svg,RASTER)
	if error!=OK: push_error("Original carry SVG failed")
	image.convert(Image.FORMAT_RGBA8)
	return image
