{config, ...}: {
  # Two SOPS files: ../../../secrets.yaml (system/general) and
  # ../home-manager/modules/pi/private.yaml (Pi/AI-related: keys, skills, private info).
  sops = {
    age.sshKeyPaths = ["/persist/etc/ssh/ssh_host_ed25519_key"];
    defaultSopsFile = ../../../secrets.yaml;

    secrets.syncthing_cert = {
      owner = "rakki";
    };
    secrets.syncthing_key = {
      owner = "rakki";
    };

    secrets.soraPass = {
      neededForUsers = true;
    };

    secrets.onedriveToken = {
      owner = "rakki";
    };

    secrets.deepseekApiKey = {
      owner = "rakki";
    };

    secrets.openaiApiKey = {
      owner = "rakki";
    };

    secrets.opencodeServerPass = {
      owner = "rakki";
    };

    secrets.caldavPass = {
      owner = "rakki";
    };

    secrets.lrdMailPass = {
      owner = "rakki";
    };

    secrets.lucky-info = {
      sopsFile = ../home-manager/modules/pi/private.yaml;
      owner = "rakki";
    };
    secrets.skillFireflyPrivate = {
      sopsFile = ../home-manager/modules/pi/private.yaml;
      owner = "rakki";
    };
    secrets.skillLumisPrivate = {
      sopsFile = ../home-manager/modules/pi/private.yaml;
      owner = "rakki";
    };
    secrets.webSearchJson = {
      sopsFile = ../home-manager/modules/pi/private.yaml;
      owner = "rakki";
    };
    secrets.anthropicApiKey = {
      sopsFile = ../home-manager/modules/pi/private.yaml;
      owner = "rakki";
    };
    #Charm (free ai api 10m tokensish/month)
    secrets.hyperApiKey = {
      sopsFile = ../home-manager/modules/pi/private.yaml;
      owner = "rakki";
    };
  };

  sops.templates."rclone-onedrive.conf" = {
    owner = "rakki";
    content = ''
      [onedrive]
      type = onedrive
      token = ${config.sops.placeholder.onedriveToken}
      drive_id = FA1D85EC1252599A
      drive_type = personal
    '';
  };
}
