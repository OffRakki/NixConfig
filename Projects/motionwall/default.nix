{
  pkgs,
  gslapper,
}: let
  renderer = gslapper.overrideAttrs (old: {
    postFixup =
      old.postFixup
      + ''
        wrapProgram $out/bin/gslapper \
          --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "${pkgs.lib.makeSearchPath "lib/gstreamer-1.0" [pkgs.gst_all_1.gst-libav]}"
      '';
  });
in
  pkgs.rustPlatform.buildRustPackage {
    pname = "motionwall";
    version = "0.1.0";
    src = pkgs.lib.cleanSource ./.;
    cargoHash = "sha256-w5rDDxThs2B/hmxbrgGGC4Uz+IcpDMJGO8CqmdNAHBs=";
    nativeBuildInputs = [pkgs.makeWrapper];
    nativeCheckInputs = [pkgs.ffmpeg pkgs.luau];
    postCheck = ''
      sed '/-- @panel@/r plugin/panel.luau' tests/picker.luau > picker-test.luau
      luau picker-test.luau
    '';
    postInstall = ''
      wrapProgram $out/bin/motionwall \
        --prefix PATH : "${pkgs.lib.makeBinPath [pkgs.ffmpeg renderer]}"
      mkdir -p $out/share/noctalia-plugins/motionwall
      cp -r plugin/. $out/share/noctalia-plugins/motionwall/
      substituteInPlace $out/share/noctalia-plugins/motionwall/service.luau \
        --replace-fail '@motionwall@' "$out/bin/motionwall"
    '';
    passthru = {inherit renderer;};
    meta = {
      description = "Rust-backed Noctalia image and video wallpaper service";
      mainProgram = "motionwall";
      platforms = pkgs.lib.platforms.linux;
    };
  }
