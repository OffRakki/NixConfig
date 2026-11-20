{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.agy;

  antigravity = pkgs.antigravity-cli.overrideAttrs {
    version = "1.5.13";
    src = pkgs.fetchurl {
      url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.13-5999302598852608/linux-x64/cli_linux_x64.tar.gz";
      hash = "sha512-AUs3OHcDrKsfR81TLIu2AWemo1N7D5iR3gPxsf+pYUMHvIPEsvdVEnOwh31yJxawzZ4meC9rKlBwXbTwXhjGjw==";
    };
    meta = pkgs.antigravity-cli.meta // {platforms = ["x86_64-linux"];};
    passthru = {};
  };

  settings = pkgs.writeText "antigravity-settings.json" (builtins.toJSON {
    editor = "hx";
    model = "Gemini 4 Neon (High)";
    agentMode = "";
    toolPermission = "proceed-in-sandbox";
    enableTerminalSandbox = true;
    allowNonWorkspaceAccess = false;
  });

  workflows = import ./antigravity-workflows.nix {inherit lib pkgs;};

  launcher = pkgs.writeShellScriptBin "agy" ''
    export AGY_CLI_DISABLE_AUTO_UPDATE=true
    exec ${lib.getExe antigravity} --settings ${settings} "$@"
  '';
in {
  options.programs.agy = {
    enable = lib.mkEnableOption "the Antigravity CLI";
    remoteControl.enable = lib.mkEnableOption "the Antigravity remote-control daemon";
  };

  config = lib.mkMerge [
    {
      programs.agy = {
        enable = true;
        remoteControl.enable = true;
      };
    }
    (lib.mkIf cfg.enable {
      home.packages = [launcher];
      home.file = {
        ".gemini/config/AGENTS.md".source = ./pi/context.md;
        ".gemini/config/plugins.json".text = builtins.toJSON {
          entries = [{path = toString workflows;}];
        };
      };
    })
    (lib.mkIf (cfg.enable && cfg.remoteControl.enable) {
      home.persistence."/persist".directories = [
        {
          directory = ".gemini/antigravity-cli";
          mode = "0700";
        }
      ];

      # Sora's linger flag is persisted under /var/lib/systemd.
      systemd.user.services.antigravity-cli-daemon = {
        Unit = {
          Description = "Antigravity CLI remote-control daemon";
          StartLimitIntervalSec = 0;
        };
        Service = {
          ExecStart = "${lib.getExe launcher} remote-control serve";
          Restart = "on-failure";
          RestartSec = "10s";
          # Match agy's native unit: don't loop when sign-in is required.
          RestartPreventExitStatus = 3;
          TimeoutStopSec = "30s";
          UMask = "0077";
        };
        Install.WantedBy = ["default.target"];
      };
    })
  ];
}
