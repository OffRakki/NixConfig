{
  pkgs,
  piPackage,
  recipientPolicyFile,
}: let
  hostConfig = pkgs.writeText "mail-assistant-host.json" (builtins.toJSON {
    config = {
      mailbox = "me@ore.rs";
      selfAddress = "ciel@ore.rs";
      provider = "openai-codex/gpt-6.1-sol";
      scope = "personal-mail";
      cwd = "/home/rakki/sync/geral/Ciel/Mailbox";
      contextPaths = [];
    };
    stateDirectory = "/home/rakki/.local/state/mail-assistant";
    authPath = "/home/rakki/.pi/agent/auth.json";
    inherit recipientPolicyFile;
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
      --set PI_TELEMETRY 0
    "$out/bin/mail-assistant-runner" --help
    "$out/bin/mail-assistant-runner" --selftest
  ''
