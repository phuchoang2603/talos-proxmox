data "doppler_secrets" "minio" {
  project = var.doppler_project
  config  = var.doppler_config
}

provider "minio" {
  minio_server   = "minio.home.phuchoang.sbs"
  minio_user     = lookup(data.doppler_secrets.minio.map, "RUSTFS_ROOT_USER", lookup(data.doppler_secrets.minio.map, "MINIO_ROOT_USER", "minio"))
  minio_password = lookup(data.doppler_secrets.minio.map, "RUSTFS_ROOT_PASSWORD", lookup(data.doppler_secrets.minio.map, "MINIO_ROOT_PASSWORD", ""))
  minio_ssl      = true
  minio_region   = "us-east-1"
}

module "rustfs_users" {
  source          = "../../modules/rustfs-s3-users"
  env             = "dev"
  doppler_project = var.doppler_project
  doppler_config  = var.doppler_config
}
