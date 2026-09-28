{
  pkgs,
  ...
}:

{
  env.DOPPLER_PROJECT = "talos-proxmox";

  packages = with pkgs; [
    doppler

    jq
    gettext

    talosctl
    kubectl
  ];

  languages = {
    opentofu = {
      enable = true;
      lsp = {
        enable = true;
      };
    };
    helm = {
      enable = true;
      lsp.enable = true;
    };
  };

  treefmt = {
    config = {
      programs = {
        actionlint = {
          enable = true;
        };
        shellcheck = {
          enable = true;
          external-sources = true;
          source-path = "SCRIPTDIR";
        };
      };
    };
    enable = true;
  };
  git-hooks.hooks.treefmt.enable = true;
}
