import type { SaveData } from '../types';

export type SoundKind = 'move' | 'grow' | 'collect' | 'complete' | '滴' | '叮' | '咚';

/** Original synthesized soundscape; starts only after a user gesture. */
export class Soundscape {
  private ctx: AudioContext | null = null;
  private music: GainNode | null = null;
  private ambient: GainNode | null = null;
  private effect: GainNode | null = null;
  private timer = 0;
  private step = 0;
  constructor(private settings: SaveData['settings']) {}
  start() {
    if (this.ctx) { void this.ctx.resume().catch(() => {}); return; }
    try {
      this.ctx = new AudioContext();
      this.music = this.ctx.createGain(); this.ambient = this.ctx.createGain(); this.effect = this.ctx.createGain();
      [this.music, this.ambient, this.effect].forEach(g => g!.connect(this.ctx!.destination));
      this.configure(this.settings);
      const drone = this.ctx.createOscillator(); drone.frequency.value = 130.81; drone.type = 'sine';
      const gain = this.ctx.createGain(); gain.gain.value = .025; drone.connect(gain); gain.connect(this.ambient); drone.start();
      this.timer = window.setInterval(() => {
        if (document.hidden || this.ctx?.state !== 'running') return;
        const notes = [261.63, 329.63, 392, 523.25, 392, 329.63, 293.66, 392];
        this.tone(notes[this.step++ % notes.length], 2.3, this.music!, .055);
      }, 1800);
    } catch { /* Audio is optional in restricted browsers. */ }
  }
  configure(settings: SaveData['settings']) {
    this.settings = settings;
    if (this.music) this.music.gain.value = settings.bgm;
    if (this.effect) this.effect.gain.value = settings.sfx;
    if (this.ambient) this.ambient.gain.value = settings.ambient;
  }
  play(kind: SoundKind) {
    if (!this.ctx || !this.effect) return;
    const frequency = { move: 220, grow: 523.25, collect: 783.99, complete: 1046.5, 滴: 659.25, 叮: 880, 咚: 392 }[kind];
    this.tone(frequency, kind === 'move' ? .12 : .7, this.effect, kind === 'move' ? .025 : .07);
  }
  pause(hidden: boolean) { if (this.ctx) void (hidden ? this.ctx.suspend() : this.ctx.resume()).catch(() => {}); }
  private tone(frequency: number, duration: number, bus: GainNode, volume: number) {
    const ctx = this.ctx!; const oscillator = ctx.createOscillator(); const gain = ctx.createGain();
    oscillator.type = 'sine'; oscillator.frequency.value = frequency;
    gain.gain.setValueAtTime(0, ctx.currentTime); gain.gain.linearRampToValueAtTime(volume, ctx.currentTime + .025);
    gain.gain.exponentialRampToValueAtTime(.0001, ctx.currentTime + duration);
    oscillator.connect(gain); gain.connect(bus); oscillator.start(); oscillator.stop(ctx.currentTime + duration);
    oscillator.onended = () => { oscillator.disconnect(); gain.disconnect(); };
  }
  destroy() { clearInterval(this.timer); void this.ctx?.close(); }
}
