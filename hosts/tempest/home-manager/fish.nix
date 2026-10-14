{lib, ...}: {
  imports = [../../home-manager/profiles/fish.nix];

  programs.fish = {
    interactiveShellInit = lib.mkAfter ''
      fastfetch
    '';
    shellAliases = {
      ls = "eza";
      la = "eza -a";
    };
    shellAbbrs = {
      nrd = "sudo nixos-rebuild switch --flake $NH_FLAKE#tempest";
      cat = "bat";
    };
  };
}
