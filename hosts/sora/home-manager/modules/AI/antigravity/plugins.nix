{
  lib,
  pkgs,
}: let
  mkMarketplacePlugin = name: {
    version,
    url,
    sha256,
  }: let
    archive = pkgs.fetchurl {
      name = "antigravity-plugin-${name}-${version}.zip";
      inherit url sha256;
    };
  in
    pkgs.runCommand "antigravity-plugin-${name}-${version}" {
      nativeBuildInputs = [pkgs.unzip];
    } ''
      mkdir -p "$out"
      unzip -q "${archive}" -d "$out"
      if [ -d "$out/skills" ]; then
        find "$out/skills" -path '*/scripts/*' -type f ! -name '*.cmd' -exec chmod +x {} +
      fi
    '';

  plugins = {
    # Official marketplace (antigravity-plugins-official)
    gcalendar = {
      version = "0.0.8";
      url = "https://www.gstatic.com/antigravity/plugins/gcalendar/gcalendar.zip?v=d084b32234dc";
      sha256 = "d084b32234dc3592df42b1257efaaaa01a1f569e9d2b3864c7bedb15496f11f1";
    };
    gdocs = {
      version = "0.0.9";
      url = "https://www.gstatic.com/antigravity/plugins/gdocs/gdocs.zip?v=3735ad2fdce0";
      sha256 = "3735ad2fdce0ca8dd9390dc9bcd1a256a8a4eddb1c843b5108869afddb05d443";
    };
    gdrive = {
      version = "0.0.11";
      url = "https://www.gstatic.com/antigravity/plugins/gdrive/gdrive.zip?v=3a7d23ec6b3e";
      sha256 = "3a7d23ec6b3e322dadfdc4e7200e98a659865961fd3989b7c045a0854d4a0c56";
    };
    gmail = {
      version = "0.0.7";
      url = "https://www.gstatic.com/antigravity/plugins/gmail/gmail.zip?v=64fdbdb7282e";
      sha256 = "64fdbdb7282e3e1efbb5d459cffc6670b5cea36e8bb808ef2640f3da2f219235";
    };
    gsheets = {
      version = "0.0.8";
      url = "https://www.gstatic.com/antigravity/plugins/gsheets/gsheets.zip?v=b298cf8ca421";
      sha256 = "b298cf8ca42121e5992e0ffb7bd778290a8760fe76ddaeaa0e7836372b7dacef";
    };
    gslides = {
      version = "0.0.8";
      url = "https://www.gstatic.com/antigravity/plugins/gslides/gslides.zip?v=3d2cdf06a7f6";
      sha256 = "3d2cdf06a7f680f3b9f01bd3602746e2cf8a78626a53e991255f103a53e8b4d6";
    };

    # Partners marketplace (antigravity-plugins-partners)
    browse = {
      version = "0.3.0";
      url = "https://www.gstatic.com/antigravity/plugins-partners/browse/browse.zip?v=248434f53882";
      sha256 = "248434f53882fae6c01045d5ea1bc9d13a285afeebf42fcdc451d9a4c7eabacb";
    };
    context7 = {
      version = "1.0.1";
      url = "https://www.gstatic.com/antigravity/plugins-partners/context7/context7.zip?v=8b449f41c009";
      sha256 = "8b449f41c0097bfb61c784112da3e5b47d7a0bdddf40469156f22d1bcf3342ab";
    };
    keenable = {
      version = "1.1.0";
      url = "https://www.gstatic.com/antigravity/plugins-partners/keenable/keenable.zip?v=2af3767170eb";
      sha256 = "2af3767170ebcc8539adb70dd202e6a216d43288e937791a9abfe48473a82a08";
    };
    n8n-skills = {
      version = "1.3.0";
      url = "https://www.gstatic.com/antigravity/plugins-partners/n8n-skills/n8n-skills.zip?v=ab274b3239a2";
      sha256 = "ab274b3239a2479d101266f9b9aa0e8de7316a493c925f8d992a4ce97ec1aa3a";
    };
  };
in
  lib.mapAttrs mkMarketplacePlugin plugins
