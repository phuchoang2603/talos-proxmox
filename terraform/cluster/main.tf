module "gcp" {
  count                     = var.cloud_provider == "gcp" ? 1 : 0
  source                    = "../modules/gcp"
  project_id                = var.gcp_project_id
  region                    = var.gcp_region
  zone                      = var.gcp_zone
  cluster_name              = "${var.env}-talos"
  talos_version             = var.talos_version
  kubernetes_version        = var.kubernetes_version
  image_id                  = local.secrets.TALOS_IMAGE_ID
  management_cidrs          = local.management_cidrs
  controlplane_machine_type = coalesce(var.gcp_controlplane_machine_type, var.gcp_machine_type)
  controlplane_schedulable  = var.gcp_controlplane_schedulable
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
  source                    = "../modules/aws"
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

module "proxmox" {
  count                   = var.cloud_provider == "proxmox" ? 1 : 0
  source                  = "../modules/proxmox"
  env                     = var.env
  nodes                   = jsondecode(file("${path.module}/env/${var.env}/k8s_nodes.json"))
  vm_node_name            = var.vm_node_name
  vm_datastore_id         = var.vm_datastore_id
  vm_bridge               = var.vm_bridge
  vm_ip_gateway           = var.vm_ip_gateway
  dns_server              = var.dns_server
  talos_version           = var.talos_version
  kubernetes_version      = var.kubernetes_version
  talos_install_disk      = var.talos_install_disk
  talos_network_interface = var.talos_network_interface
}

locals {
  clusters = {
    gcp     = module.gcp
    aws     = module.aws
    proxmox = module.proxmox
  }
  cluster          = local.clusters[var.cloud_provider][0]
  management_cidrs = setunion(var.management_cidrs, toset(jsondecode(try(nonsensitive(local.secrets.CLOUD_MANAGEMENT_CIDRS), "[]"))))
  cloud_region     = var.cloud_provider == "gcp" ? var.gcp_region : (var.cloud_provider == "aws" ? var.aws_region : "")
  cloud_zone       = var.cloud_provider == "gcp" ? var.gcp_zone : (var.cloud_provider == "aws" ? var.aws_zone : "")
}
