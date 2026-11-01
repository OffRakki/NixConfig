{
  config,
  osConfig,
  pkgs,
  ...
}: let
  safe = builtins.replaceStrings ["@"] ["-at-"];
  sync = auth: {
    enable = true;
    create = "both";
    subFolders = "Verbatim";
    extraConfig = {
      account.AuthMechs = auth;
      channel = {
        Expunge = "Both";
        Remove = "None";
        SyncState = "*";
      };
    };
  };
in {
  accounts.email = {
    maildirBasePath = "Mail";
    accounts = {
      me = {
        address = "me@ore.rs";
        userName = "me@ore.rs";
        realName = "Fernando Marques";
        primary = true;
        passwordCommand = "${pkgs.coreutils}/bin/cat ${osConfig.sops.secrets.oreMailPass.path}";
        signature = {
          showSignature = "append";
          text = "Atenciosamente,\nFernando Marques.";
        };
        imap = {
          host = "email-ssl.com.br";
          port = 993;
        };
        smtp = {
          host = "email-ssl.com.br";
          port = 465;
        };
        folders = {
          inbox = "INBOX";
          sent = null;
          drafts = null;
        };
        maildir.path = safe "me@ore.rs";
        aerc = {
          enable = true;
          smtpAuth = "login";
          extraAccounts."copy-to" = "Sent";
        };
        mbsync = (sync "LOGIN") // {patterns = ["*"];};
        thunderbird = {
          enable = true;
          settings = id: {
            "mail.server.server_${id}.directory-rel" = "[ProfD]ImapMail/email-ssl.com.br";
            "mail.server.server_${id}.namespace.personal" = ''"INBOX."'';
          };
          perIdentitySettings = id: {
            "mail.identity.id_${id}.draft_folder" = "mailbox://nobody@Local%20Folders/Drafts";
            "mail.identity.id_${id}.fcc_folder" = "imap://me%40ore.rs@email-ssl.com.br/Sent";
            "mail.identity.id_${id}.reply_on_top" = 1;
            "mail.identity.id_${id}.sig_bottom" = false;
            "mail.identity.id_${id}.stationery_folder" = "imap://me%40ore.rs@email-ssl.com.br/Templates";
          };
        };
      };

      "fruteiralab@ore.rs" = {
        address = "fruteiralab@ore.rs";
        userName = "fruteiralab@ore.rs";
        realName = "Fruteira Lab";
        imap = {
          host = "email-ssl.com.br";
          port = 993;
        };
        smtp = {
          host = "email-ssl.com.br";
          port = 465;
        };
        thunderbird = {
          enable = true;
          settings = id: {
            "mail.server.server_${id}.check_new_mail" = true;
            "mail.server.server_${id}.directory-rel" = "[ProfD]ImapMail/email-ssl.com-3.br";
            "mail.server.server_${id}.max_cached_connections" = 5;
            "mail.server.server_${id}.moveTargetMode" = 1;
            "mail.server.server_${id}.namespace.personal" = ''"INBOX."'';
            "mail.server.server_${id}.spamActionTargetAccount" = "imap://fruteiralab%40ore.rs@email-ssl.com.br";
            "mail.server.server_${id}.spamActionTargetFolder" = "imap://fruteiralab%40ore.rs@email-ssl.com.br/INBOX/Mala_Direta";
            "mail.server.server_${id}.storeContractID" = "@mozilla.org/msgstore/berkeleystore;1";
            "mail.server.server_${id}.timeout" = 29;
            "mail.server.server_${id}.trash_folder_name" = "INBOX/lixo";
          };
          perIdentitySettings = id: {
            "mail.identity.id_${id}.attach_signature" = true;
            "mail.identity.id_${id}.draft_folder" = "imap://fruteiralab%40ore.rs@email-ssl.com.br/Drafts";
            "mail.identity.id_${id}.drafts_folder_picker_mode" = "0";
            "mail.identity.id_${id}.fcc_folder" = "imap://fruteiralab%40ore.rs@email-ssl.com.br/Sent";
            "mail.identity.id_${id}.fcc_folder_picker_mode" = "0";
            "mail.identity.id_${id}.htmlSigFormat" = false;
            "mail.identity.id_${id}.reply_on_top" = 1;
            "mail.identity.id_${id}.sig_bottom" = false;
            "mail.identity.id_${id}.sig_file" = "${./thunderbird/fruteira_assinatura.html}";
            "mail.identity.id_${id}.stationery_folder" = "imap://fruteiralab%40ore.rs@email-ssl.com.br/Templates";
            "mail.identity.id_${id}.tmpl_folder_picker_mode" = "0";
          };
        };
      };
    };
  };

  programs.mbsync.enable = true;
  services.mbsync = {
    enable = true;
    package = config.programs.mbsync.package;
  };
  home.persistence."/persist".directories = ["Mail"];
}
