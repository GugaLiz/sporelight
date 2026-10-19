import { build } from 'esbuild';
const output = await build({ entryPoints: ['tests/game.test.ts'], bundle: true, platform: 'node', format: 'esm', write: false });
await import(`data:text/javascript;base64,${Buffer.from(output.outputFiles[0].text).toString('base64')}`);
