const smooth = (v: number) => { const p = Math.max(0, Math.min(1, v)); return p * p * (3 - 2 * p); };
export const MENU_LOOP_MS = 24000;
const path = (t: number) => {
  const progress = t < 6600 ? smooth((t - 2400) / 4200) : 1 - smooth((t - 13500) / 4200);
  return { x: 325 + progress * 150, y: 642 - progress * 36, progress };
};
const lights = [
  [0, 390, 468], [2400, 444, 458], [5800, 548, 478], [7500, 552, 528],
  [10000, 542, 530], [11350, 542, 530], [12750, 475, 460], [14500, 340, 480],
  [16500, 282, 508], [18500, 280, 440], [21000, 390, 440], [24000, 390, 468],
];
/** All positions are feet on the foreground stone terrace, in the 1280 × 720 scene. */
export function menuVignettePose(time: number, lowMotion = false) {
  const t = lowMotion ? 0 : ((time % MENU_LOOP_MS) + MENU_LOOP_MS) % MENU_LOOP_MS;
  const hero = path(t);
  const walking = t > 2400 && t < 6600 || t > 13500 && t < 17700;
  const returning = t >= 13100 && t < 18500;
  const curious = t >= 6950 && t < 10000;
  const delighted = t >= 10000 && t < 11350;
  const distance = (returning ? 1 - hero.progress : hero.progress) * 150;
  // Whole-body transition poses: feet stay planted before changing direction.
  let key = 'idle-front', flip = false;
  if (walking) {
    key = `step-${1 + Math.floor(distance / 60 * 8) % 8}`; flip = !returning;
  } else if (t >= 1650 && t < 2000) { key = 'turn-quarter'; flip = true; }
  else if (t >= 2000 && t < 6950) { key = 'idle-side'; flip = true; }
  else if (t >= 6950 && t < 7350) { key = 'crouch-lower'; flip = true; }
  else if (t >= 7350 && t < 11750) { key = delighted ? 'crouch-happy' : 'crouch'; flip = true; }
  else if (t >= 11750 && t < 12150) { key = 'crouch-lower'; flip = true; }
  else if (t >= 12150 && t < 12500) { key = 'idle-side'; flip = true; }
  else if (t >= 12500 && t < 12750) { key = 'turn-quarter'; flip = true; }
  // 12750–13100 explicitly holds the front pose; never mirror a side pose here.
  else if (t >= 13100 && t < 13350) { key = 'turn-quarter'; }
  else if (t >= 13350 && t < 18100) { key = 'idle-side'; }
  else if (t >= 18100 && t < 18500) { key = 'turn-quarter'; }
  const buddyPath = path(Math.max(0, t - 650));
  const buddyWalking = t > 3050 && t < 7250 || t > 14150 && t < 18350;
  const index = Math.max(0, lights.findIndex((point, i) => i < lights.length - 1 && t >= point[0] && t < lights[i + 1][0]));
  const a = lights[index], b = lights[index + 1], p = smooth((t - a[0]) / (b[0] - a[0]));
  return {
    time: t, hero: { ...hero, key, walking, flip },
    buddy: { x: buddyPath.x - 74, y: buddyPath.y + 10, walking: buddyWalking, happy: curious || delighted },
    light: { x: a[1] + (b[1] - a[1]) * p, y: a[2] + (b[2] - a[2]) * p + (lowMotion ? 0 : Math.sin(t / MENU_LOOP_MS * Math.PI * 16) * 3) },
    curious, delighted,
  };
}
