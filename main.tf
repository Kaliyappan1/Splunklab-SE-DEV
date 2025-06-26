terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
  }
  required_version = ">= 1.2.0"

  backend "s3" {
    bucket         = "splunk-deployment-test"
    key            = "splunk/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# Check if key already exists using external script
data "external" "key_check" {
  program = ["${path.cwd}/scripts/check_key.sh", var.key_name, var.aws_region]
}

# Random 2-digit number generator
resource "random_integer" "suffix" {
  min = 10
  max = 99
}

# Dynamic key name selection
locals {
  key_exists     = data.external.key_check.result.exists == "true"
  suffix         = local.key_exists ? data.external.key_check.result.next_suffix : ""
  final_key_name = "${var.key_name}${local.suffix}"
}

# Generate PEM key
resource "tls_private_key" "generated_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create EC2 Key Pair
resource "aws_key_pair" "generated_key_pair" {
  key_name   = local.final_key_name
  public_key = tls_private_key.generated_key.public_key_openssh
}

# Save PEM key locally
resource "null_resource" "save_key_file" {
  provisioner "local-exec" {
    command = <<EOT
mkdir -p keys
printf "%s" '${tls_private_key.generated_key.private_key_pem}' > keys/${local.final_key_name}.pem
chmod 400 keys/${local.final_key_name}.pem
EOT
  }

  triggers = {
    key_name   = local.final_key_name
    user_email = var.usermail
    always_run = timestamp()
  }
}

resource "null_resource" "wait_for_file" {
  depends_on = [null_resource.save_key_file]

  provisioner "local-exec" {
    command = <<EOT
i=0
while [ ! -f "keys/${local.final_key_name}.pem" ] && [ $i -lt 10 ]; do
  echo "Waiting for PEM file to be written..."
  sleep 1
  i=$((i+1))
done

if [ ! -f "keys/${local.final_key_name}.pem" ]; then
  echo "Error: PEM file not found!"
  exit 1
fi
EOT
    interpreter = ["bash", "-c"]
  }
}


resource "aws_s3_object" "upload_pem_key" {
  depends_on = [null_resource.wait_for_file]

  bucket = "splunk-deployment-test"
  key    = "${var.usermail}/keys/${local.final_key_name}.pem"
  source = "${path.cwd}/keys/${local.final_key_name}.pem"
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
    HoursPerDay   = var.hoursperday
    Category      = var.category
    PlanStartDate = var.planstartdate
  }
}

# Outputs
output "final_key_name" {
  value = local.final_key_name
}

output "key_file_path" {
  value = "${path.cwd}/keys/${local.final_key_name}.pem"
}

output "s3_key_path" {
  value = "${var.usermail}/keys/${local.final_key_name}.pem"
}
