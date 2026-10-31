{pkgs, ...}: let
  source = ../home-manager/modules/pi/mail;
  credentials = "/var/lib/mail-approval-credentials";
  login = pkgs.writeShellScriptBin "mail-approval-login" ''
    exec ${pkgs.nodejs_24}/bin/node ${source}/provision.mjs show-login ${credentials}
  '';
in {
  users.groups.mail-approval.members = ["rakki"];
  environment.systemPackages = [login];
  environment.persistence."/persist".directories = [
    {
      directory = credentials;
      user = "root";
      group = "mail-approval";
      mode = "0750";
    }
  ];
  systemd.services = {
    mail-approval-credentials = {
      description = "Initialize private runtime mail approval credentials";
      wantedBy = ["multi-user.target"];
      before = ["mail-approval.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
        ExecStart = "${pkgs.nodejs_24}/bin/node ${source}/provision.mjs init ${credentials}";
        ProtectSystem = "strict";
        ReadWritePaths = [credentials];
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
    mail-approval = {
      description = "Loopback owner approval dashboard";
      wantedBy = ["multi-user.target"];
      requires = ["mail-approval-credentials.service"];
      after = ["mail-approval-credentials.service"];
      serviceConfig = {
        DynamicUser = true;
        StateDirectory = "mail-approval";
        StateDirectoryMode = "0700";
        UMask = "0077";
        LoadCredential = [
          "api-key:${credentials}/api-key"
          "password-hash:${credentials}/password-hash"
        ];
        ExecStart = "${pkgs.nodejs_24}/bin/node ${source}/approval-server.mjs /var/lib/private/mail-approval %d/api-key %d/password-hash";
        Restart = "on-failure";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        RestrictAddressFamilies = ["AF_INET"];
        IPAddressDeny = "any";
        IPAddressAllow = "localhost";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        CapabilityBoundingSet = "";
      };
    };
  };
}
