{
  pkgs,
  inputs,
  ...
}:

{
  imports = map (m: "${inputs.devenv-modules}/${m}.nix") [
    "base"
    "kubernetes"
    "opentofu"
  ];

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
    google-cloud-sdk
    azure-cli

    openspec

    talosctl
  ];

  languages.opentofu.package =
    inputs.opentofu-nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.opentofu;
}
