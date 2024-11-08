{ config, pkgs, ... }:

let
  # Load secrets from the decrypted JSON file
  secrets = builtins.fromJSON (builtins.readFile /home/cory/github.com/twittyc/twitty-codes/secrets.decrypted.json);
  domain = "cory.twitty.codes";

in {
  imports = [ <home-manager/nixos> ];
  # Basic system configuration
  networking.hostName = "twitty-codes";
  time.timeZone = "UTC";
  system.stateVersion = "24.11";

  programs.vim.defaultEditor = true;
  programs.vim.enable = true;

  nix = {
    package =  pkgs.nixVersions.latest;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  # Enable SSH
  services.openssh.enable = true;

  # User configuration
  users.defaultUserShell = pkgs.zsh;
  users.users.cory = {
    isNormalUser = true;
    useDefaultShell = true;
    extraGroups = [ "wheel" "docker" ];
    openssh.authorizedKeys.keys = [
      (builtins.readFile "/home/cory/.ssh/id_ed25519.pub")
    ];
  };

  # Home manager configuration
  home-manager.useUserPackages = true;
  home-manager.useGlobalPkgs = true;

  # Add the acme group for Nginx
  users.users.nginx.extraGroups = [ "acme" ];

  # Firewall configuration
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];

  # Allow unfree packages for 1Password CLI
  nixpkgs.config.allowUnfree = true;

  # Install packages globally
  environment.systemPackages = with pkgs; [
    git
    sops
    home-manager
    openssl
    tmux
    dig
  ];

  # Enable Docker
  virtualisation.docker.enable = true;

  # Nginx configuration
  services.nginx = {
    enable = true;
    virtualHosts = {
      "${domain}" = {
        root = "/var/www/html";
        useACMEHost = "${domain}";
        forceSSL = true;
        listen = [
          { addr = "0.0.0.0"; port = 80; }
          { addr = "0.0.0.0"; port = 443; ssl = true; }
        ];
        locations."/" = {
          proxyPass = "http://localhost:4180";
          extraConfig = ''
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "Upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
          '';
        };
      };
    };
  };

  services.oauth2-proxy = {
    enable = true;
    httpAddress = "http://127.0.0.1:4180";
    email.domains = [ "*" ];
    upstream = [ "http://127.0.0.1:8080/" ];
    cookie.secret = "${secrets.cookie_secret}";
    cookie.secure = true;
    provider = "github";
    github.org = "twittysworkspace";
    clientID = "${secrets.client_id}";
    clientSecret = "${secrets.client_secret}";
    reverseProxy = true;
  };

  services.code-server = {
    enable = true;
    user = "cory";
    userDataDir = "/home/cory/.config/code-server";
    host = "127.0.0.1";
    port = 8080;
    disableWorkspaceTrust = true;
    disableGettingStartedOverride = true;
    auth = "none"; # Auth handled by OAuth2 Proxy
  };

  # Security settings
  security.sudo.wheelNeedsPassword = false;

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "cory@twitty.codes";
      webroot = "/var/lib/acme/acme-challenge";
      group = "nginx";
    };
    certs = {
      "${domain}" = {
        webroot = "/var/lib/acme/acme-challenge";
        group = "nginx";
      };
    };
  };
}