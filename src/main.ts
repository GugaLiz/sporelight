import './styles.css';
import { createApp } from './app/createApp';

const root = document.querySelector<HTMLDivElement>('#app');

if (!root) {
  throw new Error('Missing #app root');
}

createApp(root);
