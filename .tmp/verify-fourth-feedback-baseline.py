import json, subprocess, hashlib
from pathlib import Path

root = Path('G:/works/liuli/sporelight')
engine = 'C:/Users/liuli/.cache/sporelight-godot/4.7.2/engine/Godot_v4.7.2-stable_win64_console.exe'
out = root / 'docs/qa-godot-native/fourth-feedback-20261119/baseline-compatibility'
out.mkdir(parents=True, exist_ok=True)
changes = {
 'godot/application/main.gd': [
  ('const MovementFeedback = preload("res://application/movement_feedback.gd")\n',''),
  ('_message(MovementFeedback.blocked(session.world, tile_id, "这里暂时走不到，先观察道路的连接。"))','_message("这里暂时走不到，先观察道路的连接。")')],
 'godot/application/native_movement.gd': [
  ('const MovementFeedback = preload("res://application/movement_feedback.gd")\n',''),
  ('_notify_blocked(MovementFeedback.blocked(session.world, session.world.cell(int(p.x) + offset.x, int(p.z) + offset.y), "这里还没有接通的道路。"))','_notify_blocked("这里还没有接通的道路。")'),
  ('\t\tvar direction := Vector2i(int(signf(intent.x)), 0) if absf(intent.x) >= absf(intent.y) else Vector2i(0, int(signf(intent.y)))\n\t\tvar attempted: String = session.world.cell(int(current.x) + direction.x, int(current.z) + direction.y)\n\t\t_notify_blocked(MovementFeedback.blocked(session.world, attempted, "这边还没有可走的连接。"))', '\t\t_notify_blocked("这边还没有可走的连接。")')],
 'godot/core/garden_world.gd': [
  ('return "当前控制：小苔灵。露薇原地等候。" if actor() == "buddy" else "当前控制：露薇。小苔灵原地等候。"','return "换你来帮我啦。另一位会留在原地安心等候。"'),
  ('\t\tif level.id == "1-4" and parts[1] == "bell":\n\t\t\treturn "门铃已放在这块石台上。走近可重新拾起，由露薇带回鼹鼠家门。"\n','')],
 'godot/ui/garden_hud.gd': [
  ('\tif bool(level.get("dual", false)): _status.text = "操控：" + _status.text\n',''),
  ('\tvar cooperation := FourthGuidance.cooperation(_world) if _world != null and _guidance_level == "1-4" else ""\n',''),
  (' + str(completed) + cooperation',' + str(completed)'),
  ('\tif not cooperation.is_empty(): _action_help.text = cooperation\n','')]
}
backups = {name:(root/name).read_bytes() for name in changes}
results = []
try:
 for name, pairs in changes.items():
  text = backups[name].decode('utf-8').replace('\r\n','\n')
  for before, after in pairs:
   assert text.count(before) == 1, (name,before)
   text = text.replace(before,after)
  (root/name).write_text(text,encoding='utf-8')
 for test in ['rule_application','rule_integration','native_chapter_guidance_test','native_movement_test']:
  result = subprocess.run([engine,'--headless','--path',str(root/'godot'),'--script',f'res://tests/{test}.gd'],capture_output=True,timeout=120)
  content = result.stdout + result.stderr
  (out/(test+'.log')).write_bytes(content)
  results.append({'test':test,'exitCode':result.returncode,'failed':result.returncode!=0 or b'ERROR:' in content})
finally:
 for name, data in backups.items(): (root/name).write_bytes(data)
 (out/'checks.json').write_text(json.dumps({'scope':'Temporarily reverse only this task\'s functional consumer changes; leave all earlier edits intact. Four expanded smoke failures compared to patched run. Consumers restored byte-for-byte in finally. New unused helper and cooperation function remain present.','results':results,'restored':all((root/name).read_bytes()==data for name,data in backups.items()),'sha256':{name:hashlib.sha256(data).hexdigest() for name,data in backups.items()}},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(results))
