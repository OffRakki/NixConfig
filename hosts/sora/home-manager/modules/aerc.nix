{
  config,
  pkgs,
  lib,
  ...
}: let
  tokenDir = "${config.xdg.configHome}/aerc/tokens";
  mailRoot = "${config.home.homeDirectory}/Mail";

  sasl2Plugins = pkgs.symlinkJoin {
    name = "sasl2";
    paths = [
      "${pkgs.cyrus_sasl.out}/lib/sasl2"
      "${pkgs.cyrus-sasl-xoauth2}/lib/sasl2"
    ];
  };

  aercTokenRefresh = pkgs.writeScriptBin "aerc-token-refresh" ''
    #!${pkgs.python3}/bin/python3
    import json, urllib.request, urllib.parse, sys

    token_file = sys.argv[1]
    with open(token_file) as f:
        data = json.load(f)

    payload = urllib.parse.urlencode({
        "client_id": data["client_id"],
        "client_secret": data["client_secret"],
        "refresh_token": data["refresh_token"],
        "grant_type": "refresh_token",
    }).encode()

    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    resp = urllib.request.urlopen(req)
    print(json.loads(resp.read())["access_token"])
  '';

  accounts = [
    {
      name = "Main";
      email = "offrakki@gmail.com";
    }
    {
      name = "Personal";
      email = "fernandomarques1505@gmail.com";
    }
    {
      name = "Work";
      email = "fernando12.contato@gmail.com";
    }
  ];

  encode = email: builtins.replaceStrings ["@"] ["%40"] email;
  safe = email: builtins.replaceStrings ["@"] ["-at-"] email;
  maildir = email: "${mailRoot}/${safe email}";

  # Generate aerc accounts.conf
  mkAccount = a: ''
    [${a.name}]
    source = maildir://${maildir a.email}
    outgoing = smtps+xoauth2://${encode a.email}@smtp.gmail.com:465
    outgoing-cred-cmd = ${aercTokenRefresh}/bin/aerc-token-refresh ${tokenDir}/${a.email}
    from = ${a.email}
    copy-to = true
    default = INBOX
  '';

  accountsConf = lib.concatStringsSep "\n\n" (map mkAccount accounts);

  # Generate mbsyncrc
  mkMbsyncAccount = a: ''
    IMAPAccount ${a.name}
    Host imap.gmail.com
    Port 993
    User ${a.email}
    PassCmd "${aercTokenRefresh}/bin/aerc-token-refresh ${tokenDir}/${a.email}"
    AuthMechs XOAUTH2
    TLSType IMAPS

    IMAPStore ${a.name}-remote
    Account ${a.name}

    MaildirStore ${a.name}-local
    Path ${maildir a.email}/
    Inbox ${maildir a.email}/INBOX
    SubFolders Verbatim

    Channel ${a.name}
    Far :${a.name}-remote:
    Near :${a.name}-local:
    Patterns INBOX "[Gmail]/Sent Mail" "[Gmail]/Drafts" "[Gmail]/Trash" "[Gmail]/Spam"
    Create Both
    Sync All
    Expunge Both
  '';

  mbsyncConf = lib.concatStringsSep "\n\n" (map mkMbsyncAccount accounts);
in {
  home.persistence."/persist".directories = [
    ".config/aerc"
    "Mail"
  ];

  home.packages = with pkgs; [aerc isync cyrus-sasl-xoauth2];

  home.sessionVariables.SASL_PATH = "${sasl2Plugins}";

  xdg.desktopEntries.aerc = {
    name = "Aerc";
    genericName = "Email Client";
    comment = "Read and send emails";
    exec = "aerc %U";
    icon = "mail";
    terminal = true;
    categories = ["Network" "Email" "ConsoleOnly"];
    type = "Application";
    mimeType = ["x-scheme-handler/mailto"];
  };

  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/mailto" = "aerc.desktop";
  };

  home.activation.setupMailDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "${config.home.homeDirectory}/Mail"
    ${lib.concatStringsSep "\n" (map (a: "mkdir -p ${maildir a.email}") accounts)}
    mkdir -p "${config.xdg.configHome}/aerc"
    (umask 077; cat > "${config.xdg.configHome}/aerc/accounts.conf") << 'AERCCONF'
${accountsConf}
AERCCONF
  '';

  home.file.".mbsyncrc".text = mbsyncConf;

  systemd.user = {
    services.mbsync = {
      Unit = {
        Description = "mbsync mail sync";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
      };
      Service = {
        Type = "oneshot";
        Environment = "SASL_PATH=${sasl2Plugins}";
        ExecStart = "${pkgs.isync}/bin/mbsync -a";
      };
    };
    timers.mbsync = {
      Install = {
        WantedBy = ["timers.target"];
      };
      Timer = {
        OnBootSec = "5m";
        OnUnitActiveSec = "15m";
        Persistent = true;
      };
    };
  };

  xdg.configFile."aerc/aerc.conf".text = ''
    [general]
    default-save-path = ${config.home.homeDirectory}/Downloads
    log-file = ${config.xdg.configHome}/aerc/aerc.log

    [ui]
    index-format = %D %-18.18n %-20.20r %s
    sidebar-width = 20
    sort = -r date
    next-message-on-delete = true

    [compose]
    editor = hx
    header-placeholders = To:Cc:Subject:

    [viewer]
    pager-msgs = 10
  '';

  xdg.configFile."aerc/binds.conf".text = ''
    [messages]
    C = :compose<Enter>
    D = :promote<Enter>
    q = :quit<Enter>
    Q = :quit<Enter>
  '';
}
