# ============================================================
# SOC Platform Phase 1 - Terraform Main Configuration
# Provisions AWS EC2 infrastructure for the SOC platform
# ============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Data Sources ───────────────────────────────────────────────────────────────
data "aws_ami" "ubuntu_22_04" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ── VPC ───────────────────────────────────────────────────────────────────────
resource "aws_vpc" "soc_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, { Name = "${var.project_name}-vpc" })
}

resource "aws_internet_gateway" "soc_igw" {
  vpc_id = aws_vpc.soc_vpc.id
  tags   = merge(var.common_tags, { Name = "${var.project_name}-igw" })
}

# ── Subnet ────────────────────────────────────────────────────────────────────
resource "aws_subnet" "soc_public" {
  vpc_id                  = aws_vpc.soc_vpc.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, { Name = "${var.project_name}-public-subnet" })
}

resource "aws_route_table" "soc_rt" {
  vpc_id = aws_vpc.soc_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.soc_igw.id
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-rt" })
}

resource "aws_route_table_association" "soc_rta" {
  subnet_id      = aws_subnet.soc_public.id
  route_table_id = aws_route_table.soc_rt.id
}

# ── Security Group ─────────────────────────────────────────────────────────────
resource "aws_security_group" "soc_sg" {
  name        = "${var.project_name}-sg"
  description = "SOC Platform security group"
  vpc_id      = aws_vpc.soc_vpc.id

  # SSH access (restrict to your IP in production)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
    description = "SSH access"
  }

  # Zabbix Web UI
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidrs
    description = "Zabbix Web UI"
  }

  # Kibana
  ingress {
    from_port   = 5601
    to_port     = 5601
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidrs
    description = "Kibana Dashboard"
  }

  # Elasticsearch (restrict to internal only in production)
  ingress {
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Elasticsearch HTTP (internal only)"
  }

  # Zabbix Server trapper
  ingress {
    from_port   = 10051
    to_port     = 10051
    protocol    = "tcp"
    cidr_blocks = var.allowed_agent_cidrs
    description = "Zabbix agent communication"
  }

  # Wazuh agent enrollment
  ingress {
    from_port   = 1515
    to_port     = 1515
    protocol    = "tcp"
    cidr_blocks = var.allowed_agent_cidrs
    description = "Wazuh agent enrollment"
  }

  # Wazuh agent data collection
  ingress {
    from_port   = 1514
    to_port     = 1514
    protocol    = "udp"
    cidr_blocks = var.allowed_agent_cidrs
    description = "Wazuh agent data collection"
  }

  # Wazuh syslog
  ingress {
    from_port   = 514
    to_port     = 514
    protocol    = "udp"
    cidr_blocks = var.allowed_agent_cidrs
    description = "Syslog"
  }

  # Wazuh Manager API (restrict in production)
  ingress {
    from_port   = 55000
    to_port     = 55000
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidrs
    description = "Wazuh Manager API"
  }

  # All outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-sg" })
}

# ── Key Pair ──────────────────────────────────────────────────────────────────
resource "aws_key_pair" "soc_key" {
  key_name   = "${var.project_name}-key"
  public_key = var.ssh_public_key

  tags = var.common_tags
}

# ── SOC Platform EC2 Instance ──────────────────────────────────────────────────
resource "aws_instance" "soc_server" {
  ami                    = data.aws_ami.ubuntu_22_04.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.soc_key.key_name
  subnet_id              = aws_subnet.soc_public.id
  vpc_security_group_ids = [aws_security_group.soc_sg.id]

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
    project_name = var.project_name
  }))

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-server"
    Role = "soc-platform"
  })
}

# ── Elastic IP ────────────────────────────────────────────────────────────────
resource "aws_eip" "soc_eip" {
  instance = aws_instance.soc_server.id
  domain   = "vpc"
  tags     = merge(var.common_tags, { Name = "${var.project_name}-eip" })
}
