{
  lib,
  pkgs,
  ...
}: let
  fetch = owner: repo: rev: hash:
    pkgs.fetchFromGitHub {inherit owner repo rev hash;};
  themes = {
    Zehn = fetch "yurisuika" "Zehn" "b2159e116fa0107a8b5648b641bf8aae6243aa13" "sha256-xkFvfIeOQ6NfKwHTUk3SUVI+gFLKMKpG+UslWkSqm5A=";
    MetroSteam = fetch "RoseTheFlower" "MetroSteam" "93ab3ee7030aee4200cb5439ab0205d04876d5b7" "sha256-/dpePlyze4aN9LfBD7vBKq029r80+MWacKq4Ht0Ux08=";
  };
  plugins = {
    extendium = fetch "BossSloth" "Extendium" "3f9ffb0cd9ada58a7de7f71b3ed8d094ca7130f6" "sha256-d7ip62ZNvkOfKrAeaadJlGLk0rDG5LalROgSDh7buy4=";
    non-steam-playtimes = fetch "k0d13" "steam-non-steam-playtimes" "86f4c72181bf170b1a39868e941eabfd69a04ed4" "sha256-9cUoPaQvIF7/okMrlOvXVIiCzmnw59FPqEFvlLb8txc=";
    hltb-for-millennium = fetch "jcdoll" "hltb-millennium-plugin" "49d59edf7475ceef42734627687bdb71d7d08709" "sha256-q6hCSkviga/KuGOSlLuZP/QNLobi7bao3VuJJU/Tiss=";
    browser_history = fetch "ricewind012" "steam-browser-history" "8214f3641be641610e8237f9e14a21fdcbb4a735" "sha256-B6J4wpdEhF1yN3/kuOR19u7TrXWrLKLpx6/L4w5ng+k=";
    global_launch_options = fetch "BlafKing" "steam-global-launch-options" "0043e8ccf244739c18023be80a48509b6c8afade" "sha256-A6Q5irJoN2U7zYtdI3eEFAKiO6UblhfU1F34oYl1qWs=";
  };
  sync = target: addons:
    lib.concatStringsSep "\n" (lib.mapAttrsToList (name: source: ''
        mkdir -p "${target}/${name}"
        ${pkgs.rsync}/bin/rsync -a --delete --chmod=u+rwX \
          --exclude=sessions.json --exclude=cache.json --exclude=id_cache.json --exclude=settings.json \
          ${source}/ "${target}/${name}/"
      '')
      addons);
in {
  home.activation.millenniumAddons = lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${sync "$HOME/.local/share/Steam/millennium/themes" themes}
    ${sync "$HOME/.local/share/millennium/plugins" plugins}
  '';
}
