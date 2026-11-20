extends Control
## Mainline farewell: native accessible text/buttons over a painted garden.
## This page has its own slow decorative clock; the completed world stays paused.
signal action_requested(action: String)
const Assets := preload("res://elements/element_assets.gd")
const ButtonSkin := preload("res://ui/game_hud_skin.gd")
const Vignette := preload("res://ui/menu_vignette.gd")
const LINE_INTERVAL := 1.45
const WAVE_FOOT := Vector2(256,495)
const TITLE := "微光不散，来日方长"
const PARAGRAPHS := [
	"每个人，都是一粒微光。\n不必追赶别人的脚步，你有自己的生长时节。",
	"累了，就停下来看看风景。\n听雨落在叶上，看花慢慢开放，让心接住沿途的美好。",
	"一路拾起的微光，是生命里温暖的相逢。\n那些陪伴、善意与小小的勇敢，都在悄悄照亮你。",
	"偶尔迷路，偶尔遇见难题，也没有关系。\n给自己一点时间，换个方向，或与谁并肩，路会一点点清晰。",
	"愿你按自己的节奏生长，活出属于自己的闪亮人生。\n这段旅程暂告一段落，而你的光，还会继续。"
]
var settings: Dictionary = {}
var elapsed := 0.0
var scroll := ScrollContainer.new()
var content := VBoxContainer.new()
var title_label := Label.new()
var eyebrow := Label.new()
var paragraphs: Array[Label] = []
var footer := HBoxContainer.new()
var buttons: Array[Button] = []
var background: Texture2D
var hero: Texture2D
var hero_sprite := Sprite2D.new()
var wave_frames: Array[AtlasTexture] = []
var wave_frame := 0
var hero_ground := Vector2.ZERO
var petals: Array[AtlasTexture] = []
var letter_complete := false
var foreground := Atmosphere.new()
var orb: Texture2D
var fly: Texture2D
var letter_wash := GradientTexture2D.new()
var buddy := Vignette.BuddyArt.new()
var image_rect := Rect2()
var hero_foot := Vector2.ZERO
var art_scale := 1.0
var skin := ButtonSkin.new()

class Atmosphere:
	extends Node2D
	var page: Control
	func _draw() -> void:
		page.draw_atmosphere(self,true)

func configure(values: Dictionary) -> void:
	name = "JourneyEnding"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	background = Assets.texture_for_source("res://assets/images/ending/golden-garden-v1.png")
	letter_wash.width = 4
	letter_wash.height = 512
	letter_wash.fill_from = Vector2.ZERO
	letter_wash.fill_to = Vector2(0,1)
	letter_wash.gradient = Gradient.new()
	letter_wash.gradient.offsets = PackedFloat32Array([0,.32,.47,.75,1])
	letter_wash.gradient.colors = PackedColorArray([Color(1,.96,.86,0),Color(1,.96,.86,0),Color(1,.96,.86,.28),Color(1,.96,.86,.18),Color(1,.96,.86,0)])
	var wave_atlas := Assets.texture_for_source("res://assets/images/ending/farewell-relaxed-v2.png")
	for i in 6:
		var frame := AtlasTexture.new()
		frame.atlas = wave_atlas
		frame.region = Rect2(Vector2(i%3,i/3)*512,Vector2.ONE*512)
		frame.filter_clip = true
		wave_frames.append(frame)
	hero = wave_frames[0]
	var petal_atlas := Assets.texture_for_source("res://assets/images/ending/petals-soft-v2.png")
	for i in 4:
		var petal := AtlasTexture.new()
		petal.atlas = petal_atlas
		petal.region = Rect2(Vector2(i%2,i/2)*petal_atlas.get_size()*.5,petal_atlas.get_size()*.5)
		petal.filter_clip = true
		petals.append(petal)
	hero_sprite.texture = hero
	hero_sprite.centered = false
	hero_sprite.offset = -WAVE_FOOT
	add_child(hero_sprite)
	orb = Assets.texture_for_source("res://assets/images/menu-fx-redrawn/orb.png")
	fly = Assets.texture_for_source("res://assets/images/menu-fx-redrawn/firefly.png")
	buddy.images = {"ball":Assets.texture("ball")}
	add_child(buddy)
	buddy.z_index = 1
	foreground.page = self
	foreground.z_index = 4
	add_child(foreground)
	scroll.z_index = 5
	footer.z_index = 5
	add_child(scroll)
	scroll.name = "EndingLetterScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.tooltip_text = "轻触文字，即可显示全文。"
	scroll.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			letter_complete = true
			_update_letter())
	scroll.add_child(content)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",12)
	eyebrow.text = "微 光 苔 原  ·  旅 程 终 章"
	content.add_child(eyebrow)
	title_label.text = TITLE
	content.add_child(title_label)
	for copy: String in PARAGRAPHS:
		var paragraph := VBoxContainer.new()
		paragraph.mouse_filter = Control.MOUSE_FILTER_PASS
		paragraph.add_theme_constant_override("separation",0)
		content.add_child(paragraph)
		for line: String in copy.split("\n"):
			var label := Label.new()
			label.text = line
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_constant_override("line_spacing",0)
			label.add_theme_color_override("font_shadow_color",Color(1,.91,.53,.7))
			label.add_theme_constant_override("shadow_outline_size",3)
			label.add_theme_constant_override("shadow_offset_x",0)
			label.add_theme_constant_override("shadow_offset_y",0)
			paragraph.add_child(label)
			paragraphs.append(label)
	for label: Label in [eyebrow,title_label] + paragraphs:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color",Color("795e42"))
	title_label.add_theme_color_override("font_color",Color("9b6243"))
	title_label.add_theme_color_override("font_shadow_color",Color(1,.94,.69,.48))
	title_label.add_theme_constant_override("shadow_outline_size",4)
	title_label.add_theme_constant_override("shadow_offset_x",0)
	title_label.add_theme_constant_override("shadow_offset_y",0)
	add_child(footer)
	footer.add_theme_constant_override("separation",12)
	for entry: Array in [["map","返回花园地图"],["stay","留下看看"],["home","回到首页"]]:
		var button := Button.new()
		button.text = str(entry[1])
		button.name = "Ending_" + str(entry[0])
		button.set_meta("action",str(entry[0]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		skin.decorate_completion(button,entry[0] == "map")
		button.pressed.connect(func() -> void: action_requested.emit(str(entry[0])))
		footer.add_child(button)
		buttons.append(button)
	resized.connect(relayout)
	apply_settings(values)
	relayout()

func apply_settings(values: Dictionary) -> void:
	settings = values.duplicate(true)
	set_process(not bool(settings.get("lowMotion",false)))
	if bool(settings.get("lowMotion",false)): elapsed = 0.0
	buddy.time = elapsed*1000
	buddy.look = {"low_motion":bool(settings.get("lowMotion",false))}
	buddy.queue_redraw()
	_update_letter()
	_update_farewell()
	foreground.queue_redraw()
	queue_redraw()

func relayout() -> void:
	if background == null: return
	var extent := size
	var short := extent.y <= 460
	var portrait := extent.x < 600
	art_scale = maxf(extent.x/background.get_width(),extent.y/background.get_height()*1.016)
	var image_size := background.get_size()*art_scale
	image_rect = Rect2(Vector2((extent.x-image_size.x)*.5,extent.y*.34-image_size.y*.35),image_size)
	hero_foot = image_rect.position + image_size*Vector2(.50,.335)
	var width := minf(760,extent.x-32) if portrait else minf(840,extent.x*.70)
	var top := extent.y*(.41 if portrait else .43)
	var bottom := 88.0 if portrait else 76.0 if not short else 68.0
	scroll.position = Vector2((extent.x-width)*.5,top)
	scroll.size = Vector2(width,maxf(70,extent.y-top-bottom))
	content.add_theme_constant_override("separation",6 if short else 7)
	eyebrow.add_theme_font_size_override("font_size",10 if short else 11)
	title_label.add_theme_font_size_override("font_size",23 if portrait or short else 32)
	for paragraph: Label in paragraphs: paragraph.add_theme_font_size_override("font_size",13 if short else 14)
	# Keep all prose available in a real scroll container on compact screens.
	footer.position = Vector2(maxf(16,(extent.x-650)*.5),extent.y-bottom+14)
	footer.size = Vector2(minf(650,extent.x-32),46)
	footer.add_theme_constant_override("separation",6 if portrait else 12)
	for button: Button in buttons:
		button.add_theme_font_size_override("font_size",12 if portrait else 14)
		for state: String in ["normal","hover","pressed","focus"]:
			var style := button.get_theme_stylebox(state) as StyleBoxFlat
			style.content_margin_left = 12 if portrait else 28
			style.content_margin_right = style.content_margin_left
	buddy.position = hero_foot + Vector2(-80,24)*minf(1.2,extent.y/720)
	buddy.scale = Vector2.ONE*minf(1.15,extent.y/720)*.95
	hero_sprite.scale = Vector2.ONE*(180.0*minf(1.3,size.y/720)/464.0)
	_update_farewell()
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += minf(delta,.05)
	buddy.time = elapsed*1000
	_update_letter()
	_update_farewell()
	buddy.queue_redraw()
	foreground.queue_redraw()
	queue_redraw()

func _update_letter() -> void:
	var instant := letter_complete or bool(settings.get("lowMotion",false))
	title_label.modulate.a = 1.0 if instant else smoothstep(0.0,1.2,elapsed)
	for i in paragraphs.size():
		var age := elapsed-.7-i*LINE_INTERVAL
		paragraphs[i].modulate.a = 1.0 if instant else smoothstep(0.0,1.1,age)
		var shimmer := 0.0 if instant else sin(clampf(age/2.2,0,1)*PI)
		paragraphs[i].add_theme_color_override("font_shadow_color",Color(1,.91,.53,.36+shimmer*.50))

func _update_farewell() -> void:
	var low := bool(settings.get("lowMotion",false))
	var t := 0.0 if low else elapsed
	# Complete registered poses: no arm cutout, UV mask or joint deformation.
	wave_frame = frame_at(t)
	hero_sprite.texture = wave_frames[wave_frame]
	hero_ground = hero_foot
	hero_sprite.position = hero_foot
	hero_sprite.z_index = 0
	buddy.look = {"low_motion":low,"happy":not low}
	buddy.rotation = 0.0 if low else sin(t*1.5)*.045

static func frame_at(time: float) -> int:
	var phase := fposmod(time,5.8)
	if phase < .6 or phase >= 2.8: return 0
	var frames := [0,1,2,3,4,5,4,3,2,1,0]
	return frames[mini(10,int((phase-.6)/.2))]

func _draw() -> void:
	if background == null: return
	draw_rect(Rect2(Vector2.ZERO,size),Color("f5e2bf"))
	draw_texture_rect(background,image_rect,false)
	# A feathered ivory wash lets the opening lines sit gently over the stone,
	# without a hard card edge or low-contrast text on the carved wall.
	draw_texture_rect(letter_wash,Rect2(Vector2.ZERO,size),false)
	draw_atmosphere(self,false)
	draw_set_transform(hero_ground+Vector2(0,2),0,Vector2(1,.22))
	for shade in 3: draw_circle(Vector2.ZERO,23-shade*4,Color(.35,.25,.13,.025+shade*.02))
	draw_set_transform(Vector2.ZERO)
	var low := bool(settings.get("lowMotion",false))
	var t := 0.0 if low else elapsed
	var unit := minf(1.3,size.y/720)
	var light_at := hero_foot+Vector2(66+sin(t*.6)*9,-66+cos(t*.8)*7)*unit
	draw_texture_rect(orb,Rect2(light_at-Vector2.ONE*20*unit,Vector2.ONE*40*unit),false,Color(1,1,1,.88))
	for i in 3:
		var at := hero_foot+Vector2(cos(t*.33+i*2.1)*(110+i*9),-46+sin(t*.5+i*1.8)*23)*unit
		draw_texture_rect(fly,Rect2(at-Vector2.ONE*11*unit,Vector2.ONE*22*unit),false,Color(1,1,1,.65))

func draw_atmosphere(canvas: CanvasItem, front: bool) -> void:
	if not bool(settings.get("particles",true)): return
	var t := 0.0 if bool(settings.get("lowMotion",false)) else elapsed
	var unit := minf(1.3,size.y/720)
	for i in (42 if front else 70):
		var seed := float(i)+(107 if front else 0)
		var x := fposmod(seed*0.61803398875+.13,1.0)*size.x
		var y := fposmod(seed*.38196601125+.28-t*(.006+fposmod(seed*.17,.008)),1.0)*size.y
		x += sin(t*.25+seed*2.4)*24
		var alpha := (.25+.40*(sin(t*.7+seed)+1)*.5)
		# Keep the letter's central reading column calm.
		if y > scroll.position.y and x > size.x*.22 and x < size.x*.78: alpha *= .25
		var r := (1.0+fposmod(seed*.37,2.2))*unit*(1.1 if front else .7)
		for halo in 4:
			canvas.draw_circle(Vector2(x,y),r*(5-halo),Color(1,.79,.36,alpha*.018*(halo+1)))
		canvas.draw_circle(Vector2(x,y),r*.8,Color(1,.98,.79,alpha))
	for i in (14 if front else 22):
		var seed := float(i)+(51 if front else 0)
		var speed := .012+fposmod(seed*.007,.014)
		var y := fposmod(seed*.382+t*speed,1.15)*size.y-size.y*.08
		var x := fposmod(seed*.618+.03+t*.009,1.15)*size.x-size.x*.06+sin(t*.55+seed)*42
		var alpha := .48 if front else .30
		if y > scroll.position.y-12 and x > size.x*.20 and x < size.x*.80: alpha *= .18
		var depth := (1.0+fposmod(seed*.23,.45)) if front else (.46+fposmod(seed*.13,.3))
		var flutter := .58+.42*cos(t*.85+seed*2.1)
		canvas.draw_set_transform(Vector2(x,y),sin(t*.45+seed)*.65+seed*1.7,Vector2(flutter,1)*unit*depth)
		canvas.draw_texture_rect(petals[i%petals.size()],Rect2(-Vector2.ONE*12,Vector2.ONE*24),false,Color(1,1,1,alpha))
	canvas.draw_set_transform(Vector2.ZERO)
