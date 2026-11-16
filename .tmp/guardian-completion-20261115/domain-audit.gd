extends SceneTree
const World = preload("res://core/garden_world.gd")
const Snapshot = preload("res://contracts/snapshot_data.gd")
var checks:=0
var failures:Array[String]=[]
var records:Array=[]
func _initialize(): call_deferred("run")
func ck(ok:bool,label:String)->bool:
 checks+=1
 if not ok: failures.append(label)
 return ok
func walk(w:RefCounted,id:String,steps:Array)->bool:
 if str(w.state.actors[w.actor()])==id:return true
 var path:Array=w.path_to(id)
 if not ck(not path.is_empty(),"path "+str(w.state.turns)+" "+w.actor()+" "+str(w.state.actors[w.actor()])+"->"+id):return false
 for tile:String in path:
  if not ck(bool(w.move(tile).ok),"move "+tile):return false
  steps.append("move:"+tile)
 return true
func act(w:RefCounted,id:String,steps:Array)->bool:
 var r:Dictionary=w.act(id)
 if not ck(bool(r.ok),"act "+id+" "+str(r)):return false
 steps.append(id)
 return true
func run():
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/reference.json"))
 var entry:Dictionary={}
 for e:Dictionary in fixture.cases:
  if e.name=="authored/3-4":entry=e
 for inner in range(4):
  for water in range(4):
   var saved:Dictionary=entry.steps[48].snapshot.duplicate(true)
   saved.turns.inner=inner;saved.turns.water=water
   var w:=World.new("3-4",saved)
   var steps:Array=[]

   if not ck(Snapshot.equivalent(w.snapshot(),saved),"exact saved variant "+str([inner,water])):continue
   # Screenshot post-star high bank. Original mechanics, no invented route.
   var ok:=walk(w,"m:lift:0:0",steps)
   if ok:ok=act(w,"valve:lift",steps)
   if ok:ok=walk(w,"f:1:-4",steps)
   if ok:ok=walk(w,"m:inner:0:0",steps)
   for i in range(4):
    if not ok or int(w.state.turns.inner)==1:break
    ok=act(w,"turn:inner",steps)
   if ok:ok=walk(w,"f:-4:0",steps)
   if ok:ok=act(w,"switch",steps)
   for i in range(4):
    if not ok or int(w.state.turns.water)==1:break
    ok=act(w,"valve:water",steps)
   if ok:ok=walk(w,"f:-4:0",steps)
   if ok:ok=act(w,"switch",steps)
   if ok:ok=act(w,"repair",steps)
   ck(ok and bool(w.state.completed),"complete "+str([inner,water]))
   records.append({"inner":inner,"water":water,"completed":w.state.completed,"steps":steps,"hintAtStart":World.new("3-4",saved).hint().message})
 print(JSON.stringify({"checks":checks,"passed":failures.is_empty(),"failures":failures,"records":records,"scope":"Prepared legal post-star states; domain only, not physical GPU or exact user save."}))
 quit(0 if failures.is_empty() else 1)



