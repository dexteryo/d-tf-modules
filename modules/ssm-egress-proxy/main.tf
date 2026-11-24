locals {
  full_name = join("-", compact([var.name, var.environment, var.name_suffix]))
}

data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

resource "aws_iam_role" "this" {
  name = local.full_name
  tags = merge(var.tags, { Name = local.full_name })

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "Ec2AssumesRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = local.full_name
  role = aws_iam_role.this.name
  tags = merge(var.tags, { Name = local.full_name })
}

resource "aws_security_group" "this" {
  name_prefix = "${local.full_name}-"
  description = "Egress proxy ${local.full_name}: no ingress, reached only through SSM port forwarding"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = local.full_name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "https" {
  for_each = toset(var.egress_ipv4_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "HTTPS to Systems Manager, the package repositories and the proxied destinations"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
  tags              = var.tags
}

resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized               = true
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    proxy_port      = var.proxy_port
    allowed_domains = var.allowed_domains
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = var.kms_key_arn
  }

  tags        = merge(var.tags, { Name = local.full_name })
  volume_tags = merge(var.tags, { Name = local.full_name })

  lifecycle {
    ignore_changes = [ami]
  }
}
