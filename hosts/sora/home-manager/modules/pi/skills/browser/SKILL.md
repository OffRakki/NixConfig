---
name: browser
description: Automate live websites with agent_browser for navigation, extraction, forms, screenshots, downloads, and authenticated browser workflows.
---

# Browser

Use the native `agent_browser` tool. Do not maintain a second Playwright helper.

## Workflow

1. `open` the URL.
2. Take an interactive snapshot with `snapshot -i`.
3. Act on current `@refs` or use a semantic locator.
4. Re-snapshot after navigation, scrolling, or rerendering.
5. Verify the final page state and any requested artifact.

Batch reads and same-page actions when safe. Split the workflow before navigation
or form submission because references can become stale.

## Tool choice

- Use `fetch_content` for readable public pages, PDFs, GitHub repositories, and videos.
- Use `agent_browser` when JavaScript, interaction, login state, screenshots, or downloads matter.
- Use `qa` mode for lightweight page assertions and console/network checks.
- Use `sessionMode = "fresh"` for launch-scoped browser flags.

## Safety

- Stop before purchases, orders, posts, or final submit actions unless Lucky explicitly authorizes that exact action.
- Never expose credentials in tool arguments or chat. Use an approved browser profile or credential workflow.
- Treat `waited: timeout` as inconclusive, not success.
- Save artifacts to the exact requested path and verify the tool's artifact details before claiming completion.
