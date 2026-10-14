{pkgs, ...}: {
  services = {
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
