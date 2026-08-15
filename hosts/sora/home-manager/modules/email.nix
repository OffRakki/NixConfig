{...}: {
  accounts.email.accounts = {
    "me@lrd.rs" = {
      address = "me@lrd.rs";
      userName = "me@lrd.rs";
      realName = "Fernando Marques";
      primary = true;
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
    };
  };
}
