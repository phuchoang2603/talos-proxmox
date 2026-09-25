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
    kubernetes-helm
    awscli2
  ];

  languages = {
    opentofu = {
      enable = true;
      lsp = {
        enable = true;
      };
    };
  };
}
