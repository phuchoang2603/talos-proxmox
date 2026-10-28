module "aws" {
  source = "../../aws"

  env                        = var.env
  region                     = var.aws_region
  vpc_cidr                   = var.aws_vpc_cidr
  availability_zones         = var.aws_availability_zones
  ami_id                     = var.aws_ami_id
  gpu_ami_id                 = try(local.secrets.AWS_GPU_AMI_ID, "")
  talos_version              = var.talos_version
  kubernetes_version         = var.kubernetes_version
  cluster_name               = "${var.env}-talos"
  management_cidrs           = setunion(var.aws_management_cidrs, toset(jsondecode(nonsensitive(local.secrets.AWS_MANAGEMENT_CIDRS))))
  controlplane_instance_type = var.aws_controlplane_instance_type
}
