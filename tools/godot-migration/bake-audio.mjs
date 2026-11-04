import {mkdir, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

// Matches src/app/game/audio.ts. Audio is baked for both native and Web exports.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const output = path.join(root, 'godot/assets/audio');
const sampleRate = 44100;
const tones = {move: [220, .12, .025], grow: [523.25, .7, .07], collect: [783.99, .7, .07], complete: [1046.5, .7, .07], tick: [659.25, .7, .07], chime: [880, .7, .07], thump: [392, .7, .07]};

function tone(buffer, offset, frequency, duration, volume) {
  const start = Math.round(offset * sampleRate);
  for (let i = 0; i < Math.round(duration * sampleRate); i++) {
    const time = i / sampleRate;
    const gain = time <= .025 ? volume * time / .025 : volume * Math.pow(.0001 / volume, (time - .025) / (duration - .025));
    buffer[start + i] += Math.sin(2 * Math.PI * frequency * time) * gain;
  }
}

function wave(samples, loop = false) {
  const pcmSize = samples.length * 2;
  // smpl loop chunk lets AudioStreamWAV repeat seamlessly without editor metadata.
  const header = Buffer.alloc(44);
  header.write('RIFF', 0); header.writeUInt32LE(36 + pcmSize + (loop ? 68 : 0), 4); header.write('WAVE', 8);
  header.write('fmt ', 12); header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(1, 22);
  header.writeUInt32LE(sampleRate, 24); header.writeUInt32LE(sampleRate * 2, 28); header.writeUInt16LE(2, 32); header.writeUInt16LE(16, 34);
  header.write('data', 36); header.writeUInt32LE(pcmSize, 40);
  const pcm = Buffer.alloc(pcmSize);
  samples.forEach((sample, i) => pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, sample)) * 32767), i * 2));
  if (!loop) return Buffer.concat([header, pcm]);
  const smpl = Buffer.alloc(68); smpl.write('smpl', 0); smpl.writeUInt32LE(60, 4);
  smpl.writeUInt32LE(Math.round(1e9 / sampleRate), 16); smpl.writeUInt32LE(60, 20); smpl.writeUInt32LE(1, 36);
  smpl.writeUInt32LE(samples.length - 1, 56);
  return Buffer.concat([header, pcm, smpl]);
}

await mkdir(output, {recursive: true});
const manifest = {source: 'src/app/game/audio.ts', sampleRate, channels: 1, encoding: 'PCM16', files: []};
for (const [name, [frequency, duration, volume]] of Object.entries(tones)) {
  const samples = new Float32Array(Math.ceil((duration + .02) * sampleRate));
  tone(samples, 0, frequency, duration, volume);
  await writeFile(path.join(output, `${name}.wav`), wave(samples));
  manifest.files.push({file: `${name}.wav`, duration: samples.length / sampleRate, frequency, sourceGain: volume, loop: false});
}
const notes = [261.63, 329.63, 392, 523.25, 392, 329.63, 293.66, 392];
const musicDuration = notes.length * 1.8;
const music = new Float32Array(Math.round(musicDuration * sampleRate));
// Render the preceding cycle as well so the last note's release crosses the loop.
for (let cycle = -1; cycle <= 0; cycle++) {
  const extended = new Float32Array(Math.ceil((musicDuration + 2.3) * sampleRate));
  for (let i = 0; i < notes.length; i++) tone(extended, i * 1.8, notes[i], 2.3, .055);
  const cycleOffset = Math.round(cycle * musicDuration * sampleRate);
  for (let i = 0; i < extended.length; i++) {
    const target = i + cycleOffset;
    if (target >= 0 && target < music.length) music[target] += extended[i];
  }
}
await writeFile(path.join(output, 'music.wav'), wave(music, true));
manifest.files.push({file: 'music.wav', duration: musicDuration, loop: true, notes});
// Choose an integer number of cycles, keeping the pitch within sample rounding
// error of the source while avoiding a discontinuity at the loop seam.
const ambientCycles = 262;
const ambient = new Float32Array(Math.round(ambientCycles * sampleRate / 130.81));
for (let i = 0; i < ambient.length; i++) ambient[i] = Math.sin(2 * Math.PI * ambientCycles * i / ambient.length) * .025;
await writeFile(path.join(output, 'ambient.wav'), wave(ambient, true));
manifest.files.push({file: 'ambient.wav', duration: ambient.length / sampleRate, frequency: ambientCycles * sampleRate / ambient.length, sourceFrequency: 130.81, sourceGain: .025, loop: true});
await writeFile(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(JSON.stringify({output, files: manifest.files.length, sampleRate}));
