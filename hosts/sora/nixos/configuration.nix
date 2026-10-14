{
  inputs,
  lib,
  config,
  pkgs,
  outputs,
  nixConfigRoot,
  ...
}: {
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
    inputs.nix-minecraft.nixosModules.minecraft-servers
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager
    ../../modules
    ./containers
    ./overlays.nix
    ./nix.nix
    ./secrets.nix
    ./services.nix
    ./boot.nix
    ./hardware-configuration.nix
    ./rapoo-vt9pro.nix
    ./packages.nix
    ./fonts.nix
    ./users.nix
    ./tailscale.nix
    ./kdeconnect.nix
    ./sunshine.nix
    ./firefly.nix
    ./mcServers.nix
    ./ASF.nix
  ];

  programs.ydotool.enable = true;

  home-manager = {
    extraSpecialArgs = {inherit inputs outputs nixConfigRoot;};
    backupFileExtension = "backup";
    useGlobalPkgs = true;
    users = {
      # Import your home-manager config
      rakki = import ../home-manager/home.nix;
    };
  };

  virtualisation.waydroid = {
    enable = true;
    package = pkgs.waydroid-nftables;
  };

  environment.sessionVariables = {
    # DLSS 4+
    PROTON_DLSS_UPGRADE = 1;
    DXVK_NVAPI_DRS_NGX_DLSS_SR_OVERRIDE_RENDER_PRESET_SELECTION = "DEFAULT";

    __GL_GSYNC_ALLOWED = 1;
    __GL_VRR_ALLOWED = 1;
    __GL_SHADER_DISK_CACHE = 1;
    __GL_SHADER_DISK_CACHE_PATH = "/home/rakki/.nv/shaderCache";
    __GL_SHADER_DISK_CACHE_SIZE = 107374182400; # 100GB
    __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = 1; # Essentially unlimited cache
    AQ_DRM_DEVICES = "/dev/dri/card1";
    NVD_BACKEND = "direct";
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    GTK_IM_MODULE = "";
    QT_STYLE_OVERRIDE = "gtk3";
    QT_QPA_PLATFORM = "wayland";
    CLUTTER_BACKEND = "wayland";
    EGL_PLATFORM = "wayland";
    GDK_BACKEND = "wayland,x11";
    GDK_SCALE = "1";
    NIXOS_OZONE_WL = "1";
    MOZ_DISABLE_RDD_SANDBOX = "1";
    MOZ_ENABLE_WAYLAND = 1;
    PROTON_USE_NTSYNC = 1;
    TERMINAL = "kitty";
    EDITOR = "hx";
  };

  console.useXkbConfig = true;

  programs = {
    gpu-screen-recorder.enable = true;

    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        vulkan-loader
        libGL
        glfw
        fuse
        glib
      ];
    };

    appimage = {
      enable = true;
      binfmt = true;
      package = pkgs.appimage-run.override {extraPkgs = pkgs: [pkgs.icu];};
    };

    hyprland = {
      enable = true;
      withUWSM = false;
    };

    dconf.enable = true;

    direnv.nix-direnv.enable = true;

    java = {
      enable = true;
      package = pkgs.jre;
    };
  };

  security = {
    sudo.enable = false;
    sudo-rs = {
      enable = true;
      execWheelOnly = true;
      wheelNeedsPassword = true;
    };
    wrappers.sudo-rs = {
      source = "${lib.getExe pkgs.sudo-rs}";
      setuid = true;
      setgid = true;
      owner = "0";
      group = "0";
    };
    rtkit.enable = true;
    polkit = {
      enable = true;
      extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (
            subject.isInGroup("wheel")
              && (
                action.id == "org.freedesktop.login1.reboot" ||
                action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
                action.id == "org.freedesktop.login1.power-off" ||
                action.id == "org.freedesktop.login1.power-off-multiple-sessions"
              )
            )
          {
            return polkit.Result.YES;
          }
        })
      '';
    };
    pam.services = {
      gdm-password.enableGnomeKeyring = true;
      hyprlock = {};
    };
  };

  virtualisation.libvirtd.enable = true;

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.supportedLocales = [
    "en_US.UTF-8/UTF-8"
    "pt_BR.UTF-8/UTF-8"
  ];

  i18n.extraLocaleSettings = {
    LC_ALL = "en_US.UTF-8";
  };

  systemd = {
    services = {
      mpd = {
        environment = {
          XDG_RUNTIME_DIR = "/run/user/${toString config.users.users.rakki.uid}"; # User-id must match above user. MPD will look inside this directory for the PipeWire socket.
        };
      };
    };
    settings.Manager = {
      DefaultTimeoutStopSec = "10s";
    };
  };

  time.timeZone = lib.mkDefault "America/Sao_Paulo";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
