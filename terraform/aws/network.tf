resource "aws_vpc" "worker" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${local.name}-vpc" })
}

resource "aws_subnet" "worker" {
  vpc_id                  = aws_vpc.worker.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 0)
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(local.tags, { Name = "${local.name}-public" })
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
  subnet_id      = aws_subnet.worker.id
  route_table_id = aws_route_table.public.id
}
