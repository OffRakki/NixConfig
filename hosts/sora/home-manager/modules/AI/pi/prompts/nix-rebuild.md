---
description: Rebuild and switch NixOS configuration
---
Perform a full NixOS rebuild for the current host:

1. Ensure jj state is synced: `jj bookmark move master --to '@' && jj git export`
2. Build first: `nixos-rebuild build --flake /home/rakki/Projects/NixConfig`
3. If build succeeds, spawn kitty to apply: `kitty --directory /home/rakki/Projects/NixConfig -e sh -c 'nh os switch /home/rakki/Projects/NixConfig || exec bash'`

Important: always build first, then apply. Never skip the build step.
