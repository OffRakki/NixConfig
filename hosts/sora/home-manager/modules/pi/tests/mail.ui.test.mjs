import assert from 'node:assert/strict';
import { test } from 'node:test';
import { renderDashboard, renderLogin } from '../mail/approval-ui.mjs';

test('dashboard uses fluid width and explicit one/two/three-column responsive layouts', () => {
  const html = renderDashboard({ rows: [], counts: {}, total: 0, index: 0, size: 32, q: '', status: 'all', csrf: 'offline-fixture' });
  assert.ok(!html.includes('max-width:1200px'));
  assert.match(html, /main\{max-width:none/);
  assert.match(html, /\.queue\{display:grid;grid-template-columns:minmax\(0,1fr\)/);
  assert.match(html, /@media\(min-width:1440px\).*grid-template-columns:repeat\(2,minmax\(0,1fr\)\)/);
  assert.match(html, /@media\(min-width:2600px\).*grid-template-columns:repeat\(3,minmax\(0,1fr\)\)/);
  assert.match(html, /\.request-top\{[^}]*flex-wrap:wrap/);
  assert.match(html, /border-radius:0!important/);
  // The login form remains readable rather than stretching across an ultrawide display.
  assert.match(renderLogin('offline-fixture'), /\.login\{max-width:460px/);
});
