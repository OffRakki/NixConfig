{
  imports = [
    ../../home-manager/profiles/base.nix
    ./persistence.nix
    ./fish.nix
    ./fastfetch.nix
  ];

  home = {
    username = "tmpst";
    homeDirectory = "/home/tmpst";
  };
}
