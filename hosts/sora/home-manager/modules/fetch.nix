{pkgs, ...}: {
  home.packages = [
    (pkgs.fetch.overrideAttrs {
      version = "2.2.1";
      src = pkgs.fetchFromGitHub {
        owner = "areofyl";
        repo = "fetch";
        rev = "5297ad46acf2afb676ddc56aa8f278bd591fb9e6";
        hash = "sha256-WEjjtCRsqWOTzmZS4xnz+2l0sH9ivNSb3kSfu9Hzk/4=";
      };
    })
  ];

  xdg.configFile."fetch/config".text = ''
    uptime
    os
    kernel
    wm
    terminal
    shell
    cpu
    disk
    memory
    ip
    colors
    label_color=red
    separator=═
    box=1
  '';
}
