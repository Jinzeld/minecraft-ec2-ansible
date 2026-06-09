# terraform/main.tf
# Run: terraform init && terraform apply

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.41.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── SSH Key Pair ─────────────────────────────────────────────────────────────

resource "tls_private_key" "minecraft" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "minecraft" {
  key_name   = var.key_name
  public_key = tls_private_key.minecraft.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.minecraft.private_key_pem
  filename        = "${path.module}/../${var.key_name}.pem"
  file_permission = "0600"
}

# ─── Use Default VPC & Subnet ─────────────────────────────────────────────────

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ─── IAM Instance Profile ─────────────────────────────────────────────────────

data "aws_iam_instance_profile" "lab" {
  name = "LabInstanceProfile"
}

# ─── Security Group ────────────────────────────────────────────────────────────

resource "aws_security_group" "minecraft" {
  name        = "${var.project}-sg"
  description = "Minecraft server security group"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "Minecraft Java Edition"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-sg"
    Project = var.project
  }
}

# ─── EC2 Instance ─────────────────────────────────────────────────────────────

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

}

resource "aws_instance" "minecraft" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.minecraft.key_name
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.minecraft.id]
  iam_instance_profile        = data.aws_iam_instance_profile.lab.name
  associate_public_ip_address = true

  depends_on = [aws_security_group.minecraft]

  root_block_device {
    volume_size           = var.volume_size_gb
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name    = "${var.project}-server"
    Project = var.project
  }
}

# ─── Dynamic Ansible Inventory ────────────────────────────────────────────────

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    public_ip = aws_instance.minecraft.public_ip
    key_path  = abspath("${path.module}/../${var.key_name}.pem")
  })
  filename = "${path.module}/../ansible/inventory/hosts.ini"
}
