import './styles.css';
import { createApp } from './app/createApp';

const root = document.querySelector<HTMLDivElement>('#app');

if (!root) {
  throw new Error('Missing #app root');
}

const app = createApp(root);
if (import.meta.hot) import.meta.hot.dispose(() => app.destroy());
