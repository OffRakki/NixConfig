{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}: let
  token = email: "${config.xdg.configHome}/aerc/tokens/${email}";
  safe = builtins.replaceStrings ["@"] ["-at-"];
  refreshToken = pkgs.writeShellScript "aerc-token-refresh" ''
    ${lib.getExe pkgs.python3} - "$1" <<'PY'
    import json, sys, urllib.parse, urllib.request
    data = json.load(open(sys.argv[1]))
    payload = urllib.parse.urlencode({
        "client_id": data["client_id"],
        "client_secret": data["client_secret"],
        "refresh_token": data["refresh_token"],
        "grant_type": "refresh_token",
    }).encode()
    print(json.load(urllib.request.urlopen("https://oauth2.googleapis.com/token", payload))["access_token"])
    PY
  '';
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
  gmail = email: patterns: {
    address = email;
    userName = email;
    realName = "Fernando Marques";
    flavor = "gmail.com";
    passwordCommand = "${refreshToken} ${token email}";
    folders = {
      inbox = "INBOX";
      sent = null;
      drafts = null;
    };
    maildir.path = safe email;
    aerc = {
      enable = true;
      smtpAuth = "xoauth2";
      extraAccounts."copy-to" = true;
    };
    mbsync = (sync "XOAUTH2") // {inherit patterns;};
  };
in {
  accounts.email = {
    maildirBasePath = "Mail";
    accounts = {
      offrakki = gmail "offrakki@gmail.com" ["INBOX" "Linkedin" "LumisCards" "Nota Fiscal" "NuBank" "Riot" "Spotify" "Steam" "Twitch" "[Notion]" "[Gmail]/Drafts" "[Gmail]/Important" "[Gmail]/Sent Mail" "[Gmail]/Starred"];
      fernandomarques1505 = gmail "fernandomarques1505@gmail.com" ["INBOX" "Archive" "Mailspring/Snoozed" "Notes" "Personal" "Receipts" "Work" "[Gmail]/Drafts" "[Gmail]/Important" "[Gmail]/Sent Mail" "[Gmail]/Starred"];
      contato = gmail "fernando12.contato@gmail.com" ["INBOX" "[Gmail]/Drafts" "[Gmail]/Important" "[Gmail]/Sent Mail" "[Gmail]/Starred"];

      me = {
        address = "me@lrd.rs";
        userName = "me@lrd.rs";
        realName = "Fernando Marques";
        primary = true;
        passwordCommand = "${pkgs.coreutils}/bin/cat ${osConfig.sops.secrets.lrdMailPass.path}";
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
        maildir.path = safe "me@lrd.rs";
        aerc = {
          enable = true;
          smtpAuth = "login";
          extraAccounts."copy-to" = true;
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
            "mail.identity.id_${id}.fcc_folder" = "imap://me%40lrd.rs@email-ssl.com.br/Sent";
            "mail.identity.id_${id}.reply_on_top" = 1;
            "mail.identity.id_${id}.sig_bottom" = false;
            "mail.identity.id_${id}.stationery_folder" = "imap://me%40lrd.rs@email-ssl.com.br/Templates";
          };
        };
      };

      "fruteiralab@lrd.rs" = {
        address = "fruteiralab@lrd.rs";
        userName = "fruteiralab@lrd.rs";
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
            "mail.identity.id_${id}.sig_file" = "${./thunderbird/fruteira_assinatura.html}";
            "mail.identity.id_${id}.stationery_folder" = "imap://fruteiralab%40lrd.rs@email-ssl.com.br/Templates";
            "mail.identity.id_${id}.tmpl_folder_picker_mode" = "0";
          };
        };
      };
    };
  };

  programs.mbsync = {
    enable = true;
    package = pkgs.isync.override {withCyrusSaslXoauth2 = true;};
  };
  services.mbsync = {
    enable = true;
    package = config.programs.mbsync.package;
  };
  home.persistence."/persist".directories = ["Mail"];
}
