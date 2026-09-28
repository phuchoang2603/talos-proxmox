resource "aws_vpc" "worker" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${local.name}-vpc" })
}

resource "aws_subnet" "worker" {
  for_each = { for i, az in var.availability_zones : az => i }

  vpc_id                  = aws_vpc.worker.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.value)
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name                     = "${local.name}-${each.key}"
    "karpenter.sh/discovery" = var.cluster_name
  })
}

resource "aws_internet_gateway" "worker" {
  vpc_id = aws_vpc.worker.id

  tags = merge(local.tags, { Name = "${local.name}-igw" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.worker.id

  tags = merge(local.tags, { Name = "${local.name}-public" })
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.worker.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.worker

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
