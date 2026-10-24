data "aws_region" "current" {}

locals {
  full_name = join("-", compact([var.name, var.environment, var.name_suffix]))
  zone_ids  = range(length(var.availability_zones))

  public_cidrs   = [for index in local.zone_ids : cidrsubnet(var.cidr_block, 8, index)]
  isolated_cidrs = [for index in local.zone_ids : cidrsubnet(var.cidr_block, 8, 10 + index)]
  private_cidrs  = [for index in local.zone_ids : cidrsubnet(var.cidr_block, 6, 4 + index)]
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = local.full_name })
}

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${local.full_name}-default" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = local.full_name })
}

resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = local.public_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${local.full_name}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.this.id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = local.private_cidrs[count.index]

  tags = merge(var.tags, {
    Name = "${local.full_name}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  })
}

resource "aws_subnet" "isolated" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.this.id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = local.isolated_cidrs[count.index]

  tags = merge(var.tags, {
    Name = "${local.full_name}-isolated-${var.availability_zones[count.index]}"
    Tier = "isolated"
  })
}

resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"

  tags = merge(var.tags, { Name = "${local.full_name}-nat-${var.availability_zones[count.index]}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count         = length(var.availability_zones)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, { Name = "${local.full_name}-${var.availability_zones[count.index]}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${local.full_name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${local.full_name}-private-${var.availability_zones[count.index]}" })
}

resource "aws_route" "private_nat" {
  count                  = length(var.availability_zones)
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${local.full_name}-isolated" })
}

resource "aws_route_table_association" "isolated" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated.id
}
