module "gcp" {
  count                     = var.cloud_provider == "gcp" ? 1 : 0
  source                    = "../../gcp"
  project_id                = var.gcp_project_id
  region                    = var.gcp_region
  zone                      = var.gcp_zone
  cluster_name              = "${var.env}-talos"
  talos_version             = var.talos_version
  kubernetes_version        = var.kubernetes_version
  image_id                  = local.secrets.TALOS_IMAGE_ID
  management_cidrs          = local.management_cidrs
  controlplane_machine_type = var.gcp_machine_type
  worker_machine_type       = var.gcp_machine_type
  gpu_enabled               = var.gcp_gpu_enabled
  gpu_zone                  = var.gcp_gpu_zone
  gpu_image_id              = try(local.secrets.TALOS_GPU_IMAGE_ID, "")
  worker_min                = var.worker_min
  worker_max                = var.worker_max
  enable_spot               = var.enable_spot
  spot_max                  = var.spot_max
}

module "aws" {
  count                     = var.cloud_provider == "aws" ? 1 : 0
  source                    = "../../aws"
  env                       = var.env
  region                    = var.aws_region
  zone                      = var.aws_zone
  cluster_name              = "${var.env}-talos"
  talos_version             = var.talos_version
  kubernetes_version        = var.kubernetes_version
  ami_id                    = local.secrets.TALOS_IMAGE_ID
  management_cidrs          = local.management_cidrs
  controlplane_machine_type = var.aws_machine_type
  worker_machine_type       = var.aws_machine_type
  worker_min                = var.worker_min
  worker_max                = var.worker_max
  enable_spot               = var.enable_spot
  spot_max                  = var.spot_max
}
locals {
  cluster          = var.cloud_provider == "gcp" ? module.gcp[0] : module.aws[0]
  management_cidrs = setunion(var.management_cidrs, toset(jsondecode(nonsensitive(local.secrets.CLOUD_MANAGEMENT_CIDRS))))
  cloud_region     = var.cloud_provider == "gcp" ? var.gcp_region : var.aws_region
  cloud_zone       = var.cloud_provider == "gcp" ? var.gcp_zone : var.aws_zone
}
