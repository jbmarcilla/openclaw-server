output "elastic_ip" {
  description = "Public Elastic IP of the server"
  value       = aws_eip.openclaw.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.openclaw.id
}

output "private_key" {
  description = "SSH private key (save to .pem file)"
  value       = tls_private_key.deploy.private_key_pem
  sensitive   = true
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh -i openclaw-server-key.pem ubuntu@${aws_eip.openclaw.public_ip}"
}

output "admin_panel_url" {
  description = "Admin panel URL"
  value       = "http://${aws_eip.openclaw.public_ip}"
}

output "post_deploy" {
  description = "Steps after terraform apply"
  value       = <<-EOT

    === POST-DEPLOY ===
    1. Esperar 3-5 min para que la instalacion termine
    2. Abrir: http://${aws_eip.openclaw.public_ip}
    3. Crear tu cuenta en el wizard de setup
    4. Seguir la guia en el tab "Guia" del panel
  EOT
}
