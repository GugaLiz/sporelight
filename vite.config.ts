import { defineConfig } from 'vite';
import { localStandardsPlugin } from './tools/standards/portal.mjs';

export default defineConfig({
  plugins: [localStandardsPlugin(process.cwd())],
  base: './',
  publicDir: 'assets',
  server: {
    host: '0.0.0.0',
    port: 4173
  }
});
