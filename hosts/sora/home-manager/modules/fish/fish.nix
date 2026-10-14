{lib, ...}: {
  imports = [../../../../home-manager/profiles/fish.nix];

  home.persistence."/persist".directories = [
    ".local/share/fish"
    ".local/share/zoxide"
  ];

  programs.fish = {
    interactiveShellInit = lib.mkAfter ''
      if set -q SSH_CONNECTION DISPLAY
        set -gx QT_QPA_PLATFORM xcb
        set -gx GDK_BACKEND x11
        set -e MOZ_ENABLE_WAYLAND
        set -e NIXOS_OZONE_WL
        set -e CLUTTER_BACKEND
        set -e EGL_PLATFORM
      end

      fetch

      bind ctrl-backspace backward-kill-word
      bind ctrl-delete kill-word
      bind ctrl-left prevd-or-backward-word
      bind ctrl-right nextd-or-forward-word
      bind alt-backspace backward-kill-token
      bind alt-delete kill-token
      bind alt-left backward-token
      bind alt-right forward-token
    '';
    shellAliases = {
      cp = lib.mkForce "cp --archive --recursive --verbose --interactive --progress";
    };
    shellAbbrs = {
      watch = "viddy";
      jjdn = "jj describe && jj new";
      nrd = "sudo nixos-rebuild switch --flake $NH_FLAKE#sora";
      nrdtmpst = "nixos-rebuild switch --flake $NH_FLAKE#tempest --target-host root@192.168.15.12 --sudo --no-reexec";
      myip = "curl ifconfig.me -4";
      opencode = "opencode attach http://localhost:4096";
      ls = "eza --group-directories-first";
      ll = "eza -lbF --git";
      la = "eza -lbhHigUmuSa --git";
      lt = "eza --tree --level=2";
    };
    functions.up-or-search = lib.readFile ./hist-merge.fish;
  };
}
