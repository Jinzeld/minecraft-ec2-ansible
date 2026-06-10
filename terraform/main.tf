terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ─── SSH Key Pair ─────────────────────────────────────────────────────────────

resource "aws_key_pair" "minecraft" {
  key_name   = "minecraft-key"
  public_key = file("~/.ssh/minecraft-key.pub")
}

# ─── Security Group ────────────────────────────────────────────────────────────

resource "aws_security_group" "minecraft" {
  name        = "minecraft-sg"
  description = "Minecraft server sg"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
    Name    = "minecraft-sg"
    Project = "minecraft"
  }
}

# ─── EC2 Instance ─────────────────────────────────────────────────────────────

resource "aws_instance" "minecraft" {
  ami                         = "ami-0021ac0c2e69d9c55"
  instance_type               = "t3.medium"
  key_name                    = "minecraft-key"
  vpc_security_group_ids      = [aws_security_group.minecraft.id]
  iam_instance_profile        = "LabInstanceProfile"
  associate_public_ip_address = true

  tags = {
    Name    = "minecraft-server"
    Project = "minecraft"
  }
}

# ─── Ansible Inventory File ─────────────────────────────────────────────────

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    public_ip = aws_instance.minecraft.public_ip
    key_path  = pathexpand("~/.ssh/minecraft-key")
  })
  filename = "${path.module}/../ansible/inventory/hosts.ini"
}