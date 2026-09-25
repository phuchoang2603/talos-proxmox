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

  treefmt.enable = true;
  treefmt.config.programs.actionlint.enable = true;
  treefmt.config.programs.shellcheck = {
    enable = true;
    external-sources = true;
    source-path = "SCRIPTDIR";
  };
  git-hooks.hooks.treefmt.enable = true;
  git-hooks.hooks.chart-testing = {
    enable = true;
    files = "^apps/(components|argocd)/";
    args = [ "--chart-dirs" "apps/components,apps/argocd" "--validate-maintainers=false" ];
  };
}
