{pkgs}:
pkgs.stdenvNoCC.mkDerivation rec {
  pname = "ab-download-manager";
  version = "1.10.1";

  src = pkgs.fetchurl {
    url = "https://github.com/amir1376/ab-download-manager/releases/download/v${version}/ABDownloadManager_${version}_linux_x64.tar.gz";
    hash = "sha256-2q5TLfwHIx2uAvzjcaZrUObB70ypSnBbs7XyuZaCXuc=";
  };

  nativeBuildInputs = [pkgs.autoPatchelfHook pkgs.makeWrapper];
  buildInputs = with pkgs; [
    alsa-lib
    fontconfig
    freetype
    libGL
    libxkbcommon
    stdenv.cc.cc.lib
    wayland
    libx11
    libxext
    libxi
    libxrender
    libxtst
    zlib
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/ABDownloadManager" "$out/bin" "$out/share/applications" "$out/share/pixmaps"
    cp -r . "$out/lib/ABDownloadManager"
    makeWrapper "$out/lib/ABDownloadManager/bin/ABDownloadManager" "$out/bin/ABDownloadManager" \
      --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath [pkgs.fontconfig]}
    ln -s "$out/lib/ABDownloadManager/bin/ABDownloadManagerCli" "$out/bin/ABDownloadManagerCli"
    ln -s "$out/lib/ABDownloadManager/bin/ABDownloadManagerNativeMessagingHost" "$out/bin/ABDownloadManagerNativeMessagingHost"
    ln -s "$out/lib/ABDownloadManager/lib/ABDownloadManager.png" "$out/share/pixmaps/ab-download-manager.png"
    cat > "$out/share/applications/com.abdownloadmanager.desktop" <<EOF
    [Desktop Entry]
    Name=AB Download Manager
    Comment=Manage and organize downloads
    Categories=Network;FileTransfer;
    Exec=ABDownloadManager
    Icon=ab-download-manager
    Terminal=false
    Type=Application
    StartupWMClass=com-abdownloadmanager-desktop-AppKt
    EOF
    runHook postInstall
  '';

  meta = {
    description = "Download manager with browser integration";
    homepage = "https://github.com/amir1376/ab-download-manager";
    license = pkgs.lib.licenses.asl20;
    mainProgram = "ABDownloadManager";
    platforms = ["x86_64-linux"];
  };
}
