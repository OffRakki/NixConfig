{pkgs, ...}: let
  mailbox = "/home/rakki/sync/geral/Ciel/Mailbox";
in {
  imports = [./mail-approval.nix];
  users.groups.n8n-mailbox.members = ["rakki"];
  systemd = {
    tmpfiles.rules = [
      "d ${mailbox} 2770 rakki n8n-mailbox - -"
      # Allow traversal, but not listing, of rakki's private home directory.
      "a+ /home/rakki - - - - g:n8n-mailbox:--x"
    ];
    services.n8n.serviceConfig = {
      SupplementaryGroups = ["n8n-mailbox"];
      ReadWritePaths = [mailbox];
      UMask = "0007";
    };
  };

  services = {
    n8n = {
      enable = true;
      package = pkgs.callPackage ./n8n {};
      environment = {
        N8N_LISTEN_ADDRESS = "127.0.0.1";
        N8N_HOST = "localhost";
        N8N_PROTOCOL = "http";
        N8N_SECURE_COOKIE = false;
        N8N_RESTRICT_FILE_ACCESS_TO = mailbox;
      };
    };
    mpd = {
      enable = true;
      user = "rakki";
      settings = {
        music_directory = "/home/rakki/Music";
        audio_output = [
          {
            type = "pipewire";
            name = "Pipewire_Output";
          }
        ];
      };
    };
    xserver = {
      enable = true;
      # Enable nvidia OC
      deviceSection = ''
        Option "Coolbits" "28"
      '';
      xkb = {
        layout = "us";
        variant = "intl";
      };
    };
    greetd = {
      enable = true;
      settings = {
        initial_session = {
          command = "start-hyprland";
          user = "rakki";
        };
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --sessions /run/current-system/sw/share/wayland-sessions:/run/current-system/sw/share/xsessions --cmd start-hyprland";
          user = "greeter";
        };
      };
    };
    displayManager = {
      sessionPackages = [pkgs.hyprland];
      defaultSession = "hyprland";
    };
    openssh = {
      enable = true;
      settings = {
        # Opinionated: forbid root login through SSH.
        PermitRootLogin = "no";
        PasswordAuthentication = true;
        X11Forwarding = true;
        X11UseLocalhost = true;
      };
      hostKeys = [
        {
          path = "/persist/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];
    };
    dbus = {
      packages = [
        pkgs.gsettings-desktop-schemas
        pkgs.dconf
      ];
    };
    smartd = {
      enable = true;
      autodetect = true;
    };

    gvfs.enable = true;

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    pulseaudio.enable = false; # unstable
    envfs.enable = true;

    fstrim = {
      enable = true;
      interval = "weekly";
    };

    libinput.enable = true;

    rpcbind.enable = false;
    nfs.server.enable = false;

    flatpak.enable = true;

    blueman.enable = true;

    geoclue2.enable = true;

    fwupd.enable = true;

    upower.enable = true;

    gnome.gnome-keyring.enable = true;

    printing = {
      enable = true;
      drivers = [
        pkgs.cnijfilter2
      ];
    };
    ipp-usb.enable = true;

    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };
  };
}
