{
  pkgs,
  ...
}:

{
  env.DOPPLER_PROJECT = "talos-proxmox";

  packages = [
    pkgs.doppler
    pkgs.tflint
    pkgs.talosctl
    pkgs.kubectl
    pkgs.kubernetes-helm
    pkgs.gettext
  ];

  languages.terraform = {
    enable = true;
    version = "1.6.6";
    lsp = {
      enable = true;
      package = pkgs.terraform-ls;
    };
  };
}
