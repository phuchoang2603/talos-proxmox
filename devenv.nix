{
  pkgs,
  ...
}:

let
  tofu = pkgs.stdenvNoCC.mkDerivation {
    pname = "opentofu";
    version = "1.12.6";
    src = pkgs.fetchurl {
      url = "https://github.com/opentofu/opentofu/releases/download/v1.12.6/tofu_1.12.6_linux_amd64.zip";
      hash = "sha256-XcQ9pPdQ8zhz3CXpRYcShwnoGeVEt76QFrJVMWFTw6g=";
    };
    nativeBuildInputs = [ pkgs.unzip ];
    unpackPhase = "unzip $src";
    installPhase = "install -Dm755 tofu $out/bin/tofu";
  };
in

{
  env.DOPPLER_PROJECT = "talos-proxmox";

  packages = [
    pkgs.doppler
    pkgs.tflint
    pkgs.talosctl
    pkgs.kubectl
    pkgs.kubernetes-helm
    pkgs.jq
    pkgs.gettext
    tofu
  ];

}
