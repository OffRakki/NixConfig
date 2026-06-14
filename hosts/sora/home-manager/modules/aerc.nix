{ config, pkgs, lib, ... }:

let
  tokenDir = "${config.xdg.configHome}/aerc/tokens";

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
    { name = "Main";     email = "offrakki@gmail.com"; }
    { name = "Personal"; email = "fernandomarques1505@gmail.com"; }
    { name = "Work";     email = "fernando12.contato@gmail.com"; }
  ];

  encode = email: builtins.replaceStrings ["@"] ["%40"] email;

  mkAccount = a: ''
    [${a.name}]
    source = imaps://${encode a.email}@imap.gmail.com:993
    source-cred-cmd = ${aercTokenRefresh}/bin/aerc-token-refresh ${tokenDir}/${a.email}
    outgoing = smtps://${encode a.email}@smtp.gmail.com:465
    outgoing-cred-cmd = ${aercTokenRefresh}/bin/aerc-token-refresh ${tokenDir}/${a.email}
    from = ${a.email}
    copy-to = true
    default = INBOX
  '';

  accountsConf = lib.concatStringsSep "\n\n" (map mkAccount accounts);
in
{
  home.packages = with pkgs; [ aerc ];

  home.file."${tokenDir}/.keep".text = "";

  xdg.desktopEntries.aerc = {
    name = "Aerc";
    genericName = "Email Client";
    comment = "Read and send emails";
    exec = "aerc %U";
    icon = "mail";
    terminal = true;
    categories = [ "Network" "Email" "ConsoleOnly" ];
    type = "Application";
    mimeType = [ "x-scheme-handler/mailto" ];
  };

  xdg.mimeApps.defaultApplications = {
    "x-scheme-handler/mailto" = "aerc.desktop";
  };

  xdg.configFile."aerc/accounts.conf".text = accountsConf;

  xdg.configFile."aerc/aerc.conf".text = ''
    [general]
    default-save-path = ${config.home.homeDirectory}/Downloads
    log-file = ${config.xdg.configHome}/aerc/aerc.log

    [ui]
    index-format = %D %-18.18n %-20.20r %s
    sidebar-width = 20
    sort = newest first
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
