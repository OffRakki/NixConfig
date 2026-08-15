{...}: {
  home.persistence."/persist".directories = [".thunderbird"];

  accounts.email.accounts = {
    me.thunderbird = {
      enable = true;
      settings = id: {
        "mail.server.server_${id}.directory-rel" = "[ProfD]ImapMail/email-ssl.com.br";
        "mail.server.server_${id}.namespace.personal" = ''"INBOX."'';
      };
      perIdentitySettings = id: {
        "mail.identity.id_${id}.draft_folder" = "mailbox://nobody@Local%20Folders/Drafts";
        "mail.identity.id_${id}.fcc_folder" = "imap://me%40lrd.rs@email-ssl.com.br/Sent";
        "mail.identity.id_${id}.reply_on_top" = 1;
        "mail.identity.id_${id}.sig_bottom" = false;
        "mail.identity.id_${id}.stationery_folder" = "imap://me%40lrd.rs@email-ssl.com.br/Templates";
      };
    };

    "fruteiralab@lrd.rs".thunderbird = {
      enable = true;
      settings = id: {
        "mail.server.server_${id}.check_new_mail" = true;
        "mail.server.server_${id}.directory-rel" = "[ProfD]ImapMail/email-ssl.com-3.br";
        "mail.server.server_${id}.max_cached_connections" = 5;
        "mail.server.server_${id}.moveTargetMode" = 1;
        "mail.server.server_${id}.namespace.personal" = ''"INBOX."'';
        "mail.server.server_${id}.spamActionTargetAccount" = "imap://fruteiralab%40lrd.rs@email-ssl.com.br";
        "mail.server.server_${id}.spamActionTargetFolder" = "imap://fruteiralab%40lrd.rs@email-ssl.com.br/INBOX/Mala_Direta";
        "mail.server.server_${id}.storeContractID" = "@mozilla.org/msgstore/berkeleystore;1";
        "mail.server.server_${id}.timeout" = 29;
        "mail.server.server_${id}.trash_folder_name" = "INBOX/lixo";
      };
      perIdentitySettings = id: {
        "mail.identity.id_${id}.attach_signature" = true;
        "mail.identity.id_${id}.draft_folder" = "imap://fruteiralab%40lrd.rs@email-ssl.com.br/Drafts";
        "mail.identity.id_${id}.drafts_folder_picker_mode" = "0";
        "mail.identity.id_${id}.fcc_folder" = "imap://fruteiralab%40lrd.rs@email-ssl.com.br/Sent";
        "mail.identity.id_${id}.fcc_folder_picker_mode" = "0";
        "mail.identity.id_${id}.htmlSigFormat" = false;
        "mail.identity.id_${id}.reply_on_top" = 1;
        "mail.identity.id_${id}.sig_bottom" = false;
        "mail.identity.id_${id}.sig_file" = "${./fruteira_assinatura.html}";
        "mail.identity.id_${id}.stationery_folder" = "imap://fruteiralab%40lrd.rs@email-ssl.com.br/Templates";
        "mail.identity.id_${id}.tmpl_folder_picker_mode" = "0";
      };
    };
  };

  programs.thunderbird = {
    enable = true;
    languagePacks = ["pt-BR"];
    profiles.rakki = {
      isDefault = true;
      accountsOrder = [
        "me"
        "fruteiralab@lrd.rs"
      ];
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
