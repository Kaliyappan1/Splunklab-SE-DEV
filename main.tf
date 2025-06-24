terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.aws_region
}

# Check if key already exists using external script
data "external" "key_check" {
  program = ["${path.cwd}/scripts/check_key.sh", var.key_name]
}

# Random 2-digit number generator
resource "random_integer" "suffix" {
  min = 10
  max = 99
}

# Dynamic key name selection
locals {
  key_exists     = data.external.key_check.result.exists == "true"
  final_key_name = local.key_exists ? "${var.key_name}-${random_integer.suffix.result}" : var.key_name
}

# Create new TLS key
resource "tls_private_key" "generated_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create AWS key pair
resource "aws_key_pair" "generated_key_pair" {
  key_name   = local.final_key_name
  public_key = tls_private_key.generated_key.public_key_openssh
}

# Save private key to local 'keys' folder
resource "null_resource" "save_key_file" {
  provisioner "local-exec" {
    command = <<EOT
printf "%s" '${tls_private_key.generated_key.private_key_pem}' > keys/${local.final_key_name}.pem
chmod 400 keys/${local.final_key_name}.pem
EOT
  }

  triggers = {
    always_run = "${timestamp()}"
  }
}

# Security group random name suffix
resource "random_id" "sg_suffix" {
  byte_length = 2
}

# Security group
resource "aws_security_group" "splunk_sg" {
  name        = "splunk-security-group-${random_id.sg_suffix.hex}"
  description = "Security group for Splunk server"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8089
    to_port     = 8089
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Fetch latest RHEL 9 AMI
data "aws_ami" "rhel9" {
  most_recent = true

  filter {
    name   = "name"
    values = ["RHEL-9.*x86_64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["309956199498"]
}

# EC2 instance
resource "aws_instance" "splunk_server" {
  ami                    = data.aws_ami.rhel9.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.generated_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.splunk_sg.id]

  root_block_device {
    volume_size = var.storage_size
  }

  user_data = file("${path.cwd}/splunk-setup.sh")

  tags = {
    Name          = var.instance_name
    AutoStop      = true
    Owner         = var.usermail
    UserEmail     = var.usermail
    RunQuotaHours = var.quotahours
    Category      = var.category
  }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.generated_key.private_key_pem
      host        = self.public_ip
    }

    inline = [
      "echo '${var.ssh_public_key}' >> ~/.ssh/authorized_keys"
    ]
  }
}

# Ansible inventory file
resource "local_file" "ansible_inventory" {
  filename = "inventory.ini"

  content = <<EOF
[splunk]
${var.instance_name} ansible_host=${aws_instance.splunk_server.public_ip} ansible_user=ec2-user
EOF
}

# Ansible group vars file
resource "local_file" "ansible_group_vars" {
  filename = "group_vars/all.yml"

  content = <<EOF
---
splunk_instance:
  name: ${var.instance_name}
  private_ip: ${aws_instance.splunk_server.private_ip}
  instance_id: ${aws_instance.splunk_server.id}
  splunk_admin_password: admin123
EOF
}

# Outputs
output "final_key_name" {
  value = local.final_key_name
}

output "key_file_path" {
  value = "${path.cwd}/keys/${local.final_key_name}.pem"
}
