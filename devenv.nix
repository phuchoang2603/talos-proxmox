{
  pkgs,
  ...
}:

{
  env.DOPPLER_PROJECT = "talos-proxmox";

  enterShell = ''
    unset TF_WORKSPACE
    DOPPLER_TOKEN="$(doppler configure get token --plain 2>/dev/null)" && export DOPPLER_TOKEN || unset DOPPLER_TOKEN
    GITHUB_TOKEN="$(gh auth token 2>/dev/null)" && export GITHUB_TOKEN || unset GITHUB_TOKEN
  '';

  packages = with pkgs; [
    doppler
    gh
    awscli2

    jq

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
      };
    };
    enable = true;
  };
  git-hooks.hooks.treefmt.enable = true;
}
