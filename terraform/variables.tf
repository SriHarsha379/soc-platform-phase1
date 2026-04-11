# ============================================================
# SOC Platform Phase 1 - Terraform Variables
# ============================================================

variable "aws_region" {
  description = "AWS region to deploy the SOC platform"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "soc-platform-phase1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for the SOC server. Minimum: t3.large for MVP"
  type        = string
  default     = "t3.xlarge"

  validation {
    condition     = contains(["t3.large", "t3.xlarge", "t3.2xlarge", "m5.large", "m5.xlarge", "m5.2xlarge"], var.instance_type)
    error_message = "Instance type must be at least t3.large to run all SOC services."
  }
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 100

  validation {
    condition     = var.root_volume_size >= 50
    error_message = "Root volume must be at least 50GB for SOC platform data."
  }
}

variable "ssh_public_key" {
  description = "SSH public key for EC2 instance access"
  type        = string
  sensitive   = false
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed SSH access. Must be explicitly set; restrict to your IP(s) in production."
  type        = list(string)

  validation {
    condition     = length(var.allowed_ssh_cidrs) > 0
    error_message = "At least one SSH CIDR must be specified. Use your public IP (e.g., [\"203.0.113.0/32\"]) in production."
  }
}

variable "allowed_web_cidrs" {
  description = "CIDR blocks allowed access to web dashboards (Kibana, Zabbix)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_agent_cidrs" {
  description = "CIDR blocks allowed for Wazuh/Zabbix agent communication"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "soc-platform-phase1"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
