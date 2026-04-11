# ============================================================
# SOC Platform Phase 1 - Terraform Outputs
# ============================================================

output "soc_server_public_ip" {
  description = "Public IP address of the SOC platform server"
  value       = aws_eip.soc_eip.public_ip
}

output "soc_server_public_dns" {
  description = "Public DNS name of the SOC platform server"
  value       = aws_eip.soc_eip.public_dns
}

output "soc_server_instance_id" {
  description = "EC2 instance ID of the SOC platform server"
  value       = aws_instance.soc_server.id
}

output "kibana_url" {
  description = "Kibana dashboard URL"
  value       = "http://${aws_eip.soc_eip.public_ip}:5601"
}

output "zabbix_url" {
  description = "Zabbix web dashboard URL"
  value       = "http://${aws_eip.soc_eip.public_ip}:8080"
}

output "elasticsearch_url" {
  description = "Elasticsearch API URL (internal access only)"
  value       = "http://${aws_instance.soc_server.private_ip}:9200"
}

output "wazuh_manager_api_url" {
  description = "Wazuh Manager API URL"
  value       = "https://${aws_eip.soc_eip.public_ip}:55000"
}

output "ssh_command" {
  description = "SSH command to connect to the SOC server"
  value       = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_eip.soc_eip.public_ip}"
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.soc_vpc.id
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.soc_sg.id
}

output "setup_instructions" {
  description = "Post-deployment setup instructions"
  value       = <<-EOT
    SOC Platform Phase 1 - Deployment Complete
    ==========================================

    1. SSH into the server:
       ssh -i ~/.ssh/id_rsa ubuntu@${aws_eip.soc_eip.public_ip}

    2. Clone and configure the SOC platform:
       git clone https://github.com/SriHarsha379/soc-platform-phase1.git
       cd soc-platform-phase1
       cp .env.example .env && nano .env
       ./scripts/init-setup.sh

    3. Access the dashboards:
       Kibana:  http://${aws_eip.soc_eip.public_ip}:5601
       Zabbix:  http://${aws_eip.soc_eip.public_ip}:8080

    4. Run health checks:
       ./scripts/health-check.sh
  EOT
}
