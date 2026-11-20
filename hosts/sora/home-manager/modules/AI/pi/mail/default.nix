{
  pkgs,
  piPackage,
  piPackages,
  recipientPolicyFile,
  privateContextFile,
  apiKeyFile,
}: let
  resources = import ../resources.nix {inherit pkgs;};
  browserConfig = pkgs.writeText "mail-browser-config.json" (builtins.toJSON {
    version = 1;
    browser.executablePath = "${pkgs.chromium}/bin/chromium";
  });
  nativeBrowserConfig = pkgs.writeText "mail-native-browser-config.json" "{}";
  hostConfig = pkgs.writeText "mail-assistant-host.json" (builtins.toJSON {
    config = {
      mailbox = "me@ore.rs";
      selfAddress = "ciel@ore.rs";
      provider = "openai-codex/gpt-6.1-sol";
      scope = "personal-mail";
      cwd = "/home/rakki/sync/geral/Ciel/Mailbox";
      # Private facts are loaded only after investigation approval, never for public/safe replies.
      contextPaths = [privateContextFile];
      assistantProfile = {
        personaFile = "${resources.context}";
        shellPath = "${pkgs.bash}/bin/bash";
        browserConfigFile = "${browserConfig}";
        browserNativeConfigFile = "${nativeBrowserConfig}";
        skillPaths = ["${resources.skills}"];
        # These integrations expose tools through Pi's guarded (including nested) dispatch.
        # Delegation, scheduling, intercom and general session-control plugins stay out:
        # their child/background effects do not inherit the mail approval ledger.
        extensionPaths = map (name: "${piPackages.npmClosure}/node_modules/${name}") [
          "pi-web-access"
          "pi-agent-browser-native"
        ];
      };
    };
    stateDirectory = "/home/rakki/.local/state/mail-assistant";
    authPath = "/home/rakki/.pi/agent/auth.json";
    inherit recipientPolicyFile apiKeyFile;
    tokenFile = "/var/lib/mail-approval-credentials/api-key";
    endpoint = "http://127.0.0.1:8765";
  });
in
  pkgs.runCommand "mail-assistant-runner" {
    nativeBuildInputs = [pkgs.makeWrapper];
  } ''
    mkdir -p "$out/bin" "$out/share/mail-assistant"
    cp ${./core.mjs} "$out/share/mail-assistant/core.mjs"
    cp ${./runner.mjs} "$out/share/mail-assistant/runner.mjs"
    cp ${./safe.mjs} "$out/share/mail-assistant/safe.mjs"
    cp ${./production.mjs} "$out/share/mail-assistant/production.mjs"
    cp ${./approval-server.mjs} "$out/share/mail-assistant/approval-server.mjs"
    cp ${./approval-ui.mjs} "$out/share/mail-assistant/approval-ui.mjs"
    cp ${./Mail.candidate.json} "$out/share/mail-assistant/Mail.candidate.json"
    makeWrapper ${pkgs.nodejs_24}/bin/node "$out/bin/mail-assistant-runner" \
      --add-flags "$out/share/mail-assistant/production.mjs --config-file ${hostConfig}" \
      --set PI_PACKAGE_ROOT ${piPackage}/lib/node_modules/pi-monorepo \
      --set PI_AGENT_BROWSER_PINNED_CONFIG ${browserConfig} \
      --set PI_AGENT_BROWSER_NATIVE_CONFIG ${nativeBrowserConfig} \
      --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.agent-browser pkgs.chromium]} \
      --set PI_TELEMETRY 0
    "$out/bin/mail-assistant-runner" --help
    "$out/bin/mail-assistant-runner" --selftest
    ${pkgs.nodejs_24}/bin/node ${../tests/mail.resources.smoke.mjs} \
      ${piPackage}/lib/node_modules/pi-monorepo "$out"
  ''
