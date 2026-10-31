{
  pkgs,
  piPackage,
}:
pkgs.runCommand "mail-assistant-runner" {
  nativeBuildInputs = [pkgs.makeWrapper];
} ''
  mkdir -p "$out/bin" "$out/share/mail-assistant"
  cp ${./core.mjs} "$out/share/mail-assistant/core.mjs"
  cp ${./runner.mjs} "$out/share/mail-assistant/runner.mjs"
  cp ${./Mail.candidate.json} "$out/share/mail-assistant/Mail.candidate.json"
  makeWrapper ${pkgs.nodejs_24}/bin/node "$out/bin/mail-assistant-runner" \
    --add-flags "$out/share/mail-assistant/runner.mjs" \
    --set PI_PACKAGE_ROOT ${piPackage}/lib/node_modules/pi-monorepo \
    --set PI_OFFLINE 1 \
    --set PI_TELEMETRY 0
  "$out/bin/mail-assistant-runner" --help
  "$out/bin/mail-assistant-runner" --selftest
''
