{...}: {
  home.persistence."/persist".directories = [".thunderbird"];

  programs.thunderbird = {
    enable = true;
    languagePacks = ["pt-BR"];
    profiles.rakki = {
      isDefault = true;
      settings = {
        "extensions.activeThemeID" = "seoul-dark@mkirc.themes.thunderbird.net";
        "extensions.filtaquilla.removeFlagged.enabled" = true;
        "extensions.filtaquilla.removeKeyword.enabled" = true;
        "mail.shell.checkDefaultClient" = false;
        "mail.tabs.drawInTitlebar" = false;
        "mail.threadpane.listview" = 1;
        "mailnews.start_page.url" = "https://codeberg.org/Rakki";
        "spellchecker.dictionary" = "en-US,pt-BR";
      };
    };
    policies.ExtensionSettings = {
      "filtaquilla@mesquilla.com" = {
        installation_mode = "force_installed";
        install_url = "https://addons.thunderbird.net/thunderbird/downloads/file/1048356/filtaquilla-6.2.2-tb.xpi";
      };
      "replywithheader@myjeeva.com" = {
        installation_mode = "force_installed";
        install_url = "https://addons.thunderbird.net/thunderbird/downloads/file/1042881/replywithheader-3.3.1-tb.xpi";
      };
      "seoul-dark@mkirc.themes.thunderbird.net" = {
        installation_mode = "force_installed";
        install_url = "https://addons.thunderbird.net/thunderbird/downloads/file/1020548/seoul_dark-1.3-tb.xpi";
      };
      "macchitiounofficial@addons.thunderbird.net" = {
        installation_mode = "normal_installed";
        install_url = "https://addons.thunderbird.net/thunderbird/downloads/file/1040515/catppuccin_macchiatio_unofficial-1.1-tb.xpi";
      };
      "pt-BR@dellalibera.sf.net" = {
        installation_mode = "force_installed";
        install_url = "https://addons.thunderbird.net/thunderbird/downloads/file/1012599/verificador_ortografico_para_portugues_do_brasil-2.5-3.2.13.1webext.xpi";
      };
    };
  };
}
