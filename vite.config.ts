import { defineConfig } from 'vite';

export default defineConfig({
  base: './',
  publicDir: 'assets',
  server: {
    host: '0.0.0.0',
    port: 4173
  }
});
