# =============================================================================
# Bastion Host
# =============================================================================
# A minimal EC2 instance in a public subnet for SSH access to private
# resources like Aurora, ElastiCache, and ECS tasks. Disabled by default.
#
# Usage:
#   1. Create an EC2 key pair:  aws ec2 import-key-pair --key-name bastion --public-key-material fileb://~/.ssh/id_ed25519.pub
#   2. Set enable_bastion = true and bastion_key_name = "bastion"
#   3. SSH in:  ssh ec2-user@<bastion_public_ip>
#   4. From there:  psql -h <rds_proxy_endpoint> -U postgres -d app
# =============================================================================

# -----------------------------------------------------------------------------
# Bastion Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "bastion" {
  count = var.enable_bastion ? 1 : 0

  name        = "${local.name_prefix}-bastion-sg"
  description = "Security group for bastion host SSH access"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-bastion-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  count = var.enable_bastion ? 1 : 0

  security_group_id = aws_security_group.bastion[0].id
  description       = "SSH from allowed CIDRs"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.bastion_allowed_cidr

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-bastion-ssh" })
}

resource "aws_vpc_security_group_egress_rule" "bastion_to_internet" {
  count = var.enable_bastion ? 1 : 0

  security_group_id = aws_security_group.bastion[0].id
  description       = "To internet for package updates"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-bastion-egress" })
}

# -----------------------------------------------------------------------------
# Database and Redis access from bastion
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "database_from_bastion" {
  count = var.enable_bastion ? 1 : 0

  security_group_id            = aws_security_group.database.id
  description                  = "From Bastion host"
  from_port                    = var.database_port
  to_port                      = var.database_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.bastion[0].id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-db-from-bastion" })
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_bastion" {
  count = var.enable_bastion ? 1 : 0

  security_group_id            = aws_security_group.redis.id
  description                  = "From Bastion host"
  from_port                    = var.redis_port
  to_port                      = var.redis_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.bastion[0].id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-redis-from-bastion" })
}

# -----------------------------------------------------------------------------
# Bastion EC2 Instance
# -----------------------------------------------------------------------------

data "aws_ami" "amazon_linux" {
  count = var.enable_bastion ? 1 : 0

  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "bastion" {
  count = var.enable_bastion ? 1 : 0

  ami                    = data.aws_ami.amazon_linux[0].id
  instance_type          = var.bastion_instance_type
  key_name               = var.bastion_key_name
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.bastion[0].id]

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-bastion"
  })
}
