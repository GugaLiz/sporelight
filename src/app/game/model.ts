import { type Level, type WorldNode, totalSpores } from './levels';

export interface RunState { levelId: string; node: string; collected: string[]; activated: string[]; angles: Record<string, number>; completed: boolean }
export interface ActionResult { ok: boolean; message: string }
const clone = (state: RunState): RunState => JSON.parse(JSON.stringify(state));

export class GameModel {
  state: RunState;
  private history: RunState[] = [];
  constructor(readonly level: Level, saved?: Partial<RunState> | null) {
    this.state = { levelId: level.id, node: 'start', collected: [], activated: [], angles: {}, completed: false };
    if (saved?.levelId === level.id && level.nodes.some(n => n.id === saved.node)) {
      this.state.node = saved.node!;
      this.state.collected = [...new Set(Array.isArray(saved.collected) ? saved.collected.filter(id => level.nodes.some(n => n.id === id && n.spore)) : [])];
      const activated = Array.isArray(saved.activated) ? saved.activated : [];
      this.state.activated = [...new Set(activated.filter(id => level.nodes.some(n => n.id === id && n.mechanism)))];
      for (const node of level.nodes.filter(n => n.mechanism === 'reflect')) {
        const angle = saved.angles?.[node.id];
        if (typeof angle === 'number' && Number.isInteger(angle) && angle >= 0 && angle <= 2) this.state.angles[node.id] = angle;
      }
      // Validate reachability after loading; malformed states must not strand the player.
      if (!this.pathFrom('start', this.state.node)) this.state.node = 'start';
    }
  }
  get current(): WorldNode { return this.level.nodes.find(n => n.id === this.state.node)!; }
  get canUndo() { return this.history.length > 0; }
  get stars() { return this.state.collected.length === totalSpores(this.level) ? 3 : this.state.collected.length >= Math.ceil(totalSpores(this.level) / 2) ? 2 : 1; }
  snapshot() { return clone(this.state); }
  private checkpoint() { this.history.push(this.snapshot()); if (this.history.length > 80) this.history.shift(); }
  undo() { const previous = this.history.pop(); if (!previous) return false; this.state = previous; return true; }
  edgeOpen(from: string, to: string) {
    const edge = this.level.edges.find(e => (e.from === from && e.to === to) || (e.to === from && e.from === to));
    return !!edge && (!edge.gate || this.state.activated.includes(edge.gate));
  }
  pathTo(to: string) { return this.pathFrom(this.state.node, to); }
  private pathFrom(from: string, to: string): string[] | null {
    const queue = [[from]]; const visited = new Set([from]);
    while (queue.length) {
      const path = queue.shift()!; const current = path[path.length - 1];
      if (current === to) return path;
      for (const n of this.level.nodes) if (!visited.has(n.id) && this.edgeOpen(current, n.id)) { visited.add(n.id); queue.push([...path, n.id]); }
    }
    return null;
  }
  move(to: string): ActionResult {
    if (this.state.completed || !this.edgeOpen(this.state.node, to)) return { ok: false, message: '前方还没有路，先唤醒附近的植物吧。' };
    if (to === this.level.exit && this.level.allSpores && this.state.collected.length < totalSpores(this.level)) return { ok: false, message: '还有孢子在等你，收集齐八粒微光再来吧。' };
    this.checkpoint(); this.state.node = to;
    if (this.current.spore && !this.state.collected.includes(to)) this.state.collected.push(to);
    if (to === this.level.exit) this.state.completed = true;
    return { ok: true, message: this.state.completed ? '这一片苔原，因你而苏醒。' : this.current.mechanism ? '这里在等待一粒温柔的孢子。' : '不着急，微光会陪着你。' };
  }
  interact(time = 0, lowMotion = false): ActionResult {
    const node = this.current;
    if (this.state.completed) return { ok: false, message: '这段旅程已经完成。' };
    if (!node.mechanism) return { ok: false, message: '走到标有叶芽的石台，再播种吧。' };
    if (this.state.activated.includes(node.id)) return { ok: false, message: '这里已经醒来了，继续向前吧。' };
    if (node.mechanism === 'rhythm' && !lowMotion && time % 3000 >= 1500) return { ok: false, message: '等蓝色水膜亮起，再轻轻播种。下一阵雨很快就来。' };
    if (node.mechanism === 'sequence') {
      if (this.state.collected.length < totalSpores(this.level)) return { ok: false, message: '先找齐八粒孢子，再开始点亮星光。' };
      const next = this.state.activated.length + 1;
      if (node.order !== next) return { ok: false, message: `先去点亮第 ${next} 处星光吧。顺序是 ① → ② → ③ → ④。` };
    }
    this.checkpoint();
    if (node.mechanism === 'reflect') {
      const angle = ((this.state.angles[node.id] ?? 0) + 1) % 3;
      this.state.angles[node.id] = angle;
      if (angle !== node.angle) return { ok: true, message: '光线还差一点方向，再旋转一次反光叶。' };
    }
    this.state.activated.push(node.id);
    const messages = { grow: '花开了，花瓣变成一座小桥。', vine: '藤蔓轻轻伸展，接住前方的道路。', lily: '睡莲醒了，试着跳到下一块石台。', reflect: '微光接通了，新的道路出现了。', rhythm: '雨滴落下，睡莲接住了这段节拍。', light: '一盏苔藓灯，照亮一小片夜色。', friend: '光虫来了，花香请伙伴让出了道路。', sequence: '一束星光，回到水晶花的怀抱。' };
    return { ok: true, message: messages[node.mechanism] };
  }
  hint() {
    if (this.level.allSpores && this.state.collected.length < totalSpores(this.level)) {
      const n = this.level.nodes.find(n => n.spore && !this.state.collected.includes(n.id));
      return { node: n?.id, message: '先沿四条支路收集全部八粒孢子，亮圈标出了下一粒。' };
    }
    const next = this.level.nodes.find(n => n.mechanism && !this.state.activated.includes(n.id) && this.pathTo(n.id));
    if (!next) return { node: this.level.exit, message: '道路已经连通，去唤醒终点的花吧。支路上可能还有孢子。' };
    const detail = next.mechanism === 'reflect' ? '到亮圈处，按 E 旋转叶片，让光线朝向下一块石台。' : next.mechanism === 'rhythm' ? '到亮圈处，等水膜亮起后按 E；低动态模式不需要等待。' : next.mechanism === 'sequence' ? `去第 ${next.order} 处光点，按 E 点亮。` : '走到亮圈标出的土地，按 E 或点击「播种 / 互动」。';
    return { node: next.id, message: detail };
  }
}
