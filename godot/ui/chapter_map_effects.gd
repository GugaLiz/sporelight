extends Control
## Small paper-map vignettes, never miniature playable geometry or hit targets.
const FEATURES := {
	"1-1":"root", "1-2":"detour", "1-3":"turn", "1-4":"home",
	"2-1":"water", "2-2":"mirror", "2-3":"song", "2-4":"ferry",
	"3-1":"lantern", "3-2":"shadow", "3-3":"irrigation", "3-4":"guardian"
}
const CAPTIONS := {
	"1-1":"一芽连岸", "1-2":"绕石引芽", "1-3":"转庭相遇", "1-4":"门铃归家",
	"2-1":"水位与睡莲", "2-2":"镜叶送光", "2-3":"雨歌升台", "2-4":"载光虫渡岸",
	"3-1":"携灯开窗", "3-2":"日月留影", "3-3":"分水养根", "3-4":"根水光相连"
}
const INK := Color("8c8369")
const LEAF := Color("7d9c76")
const WATER := Color("8dbdc1")
const LIGHT := Color("ead58f")
var chapter := "valley"
var landmarks: Array[Dictionary] = []
var clock := 0.0
var low_motion := false
var paused := false
var particles := true
var frames_drawn := 0
var _pending := 0.0
var _path := PackedVector2Array()

func configure(id: String,entries: Array[Dictionary],terraces: Array) -> void:
	chapter=id;landmarks.clear();mouse_filter=Control.MOUSE_FILTER_IGNORE
	name="ChapterLivingInk";size=Vector2(1280,720)
	for index in entries.size():
		var entry:=entries[index]
		landmarks.append({"id":str(entry.id),"at":terraces[index],"unlocked":bool(entry.unlocked),"completed":bool(entry.completed)})
	# Same authored terrace path as levelSelectScene.ts; sample once, not per frame.
	_path.clear()
	var start:=Vector2(112,441)
	for segment: Array in [[Vector2(176,411),Vector2(260,390)],[Vector2(315,447),Vector2(400,477)],[Vector2(470,511),Vector2(561,485)],[Vector2(625,467),Vector2(704,465)],[Vector2(675,396),Vector2(709,320)],[Vector2(734,251),Vector2(799,201)]]:
		for step in range(16):
			var t:=step/16.0
			_path.append(start*(1-t)*(1-t)+segment[0]*2*t*(1-t)+segment[1]*t*t)
		start=segment[1]
	_path.append(start);queue_redraw()

func apply_settings(settings: Dictionary) -> void:
	low_motion=bool(settings.get("lowMotion",false));particles=bool(settings.get("particles",true));queue_redraw()

func set_paused(value: bool) -> void:
	paused=value

func _process(delta: float) -> void:
	if low_motion or paused or not is_visible_in_tree(): return
	clock+=minf(delta,.1);_pending+=delta
	if _pending<.05:return
	_pending=0;queue_redraw()

func _draw() -> void:
	frames_drawn+=1
	var t:=0.0 if low_motion else clock
	var tint:=WATER if chapter=="pond" else Color("c1b9df") if chapter=="cave" else LIGHT
	if chapter!="cloud":
		for index in range(0,_path.size(),3):
			var glint:=.45+.25*sin(index*.2-t*.7)
			draw_circle(_path[index],1.7,Color(tint,glint))
		# Keep the illustrated landscape free of extra plaques and diagrams.
		# Small pollen lights belong to the existing flowerbeds; the selected
		# level's mechanism illustration lives inside its existing paper card.
		if particles:
			for item: Dictionary in landmarks:
				if not item.unlocked: continue
				var at: Vector2=item.at+Vector2(0,-60)
				for mote in range(3):
					var p:=at+Vector2(26*cos(t*.22+mote*2.1),-12+8*sin(t*.3+mote*2.1))
					draw_circle(p,1.2,Color(tint,.18+.18*(.5+.5*sin(t*.8+mote))))
	if particles:
		# Original twenty small lights; bounded coordinates avoid the paper card.
		for index in range(20):
			var x:=float((index*137+42)%830+38)
			var y:=float((index*79+160)%410+160)-sin(t*.35+index)*7
			var alpha:=.25+.22*(.5+.5*sin(t*.65+index*1.7))
			draw_circle(Vector2(x,y),float(index%3+1),Color(tint,alpha))

