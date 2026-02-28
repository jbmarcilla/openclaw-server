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
  description = "Admin panel URL (HTTP)"
  value       = "http://${aws_eip.openclaw.public_ip}"
}

output "admin_panel_https" {
  description = "Admin panel HTTPS URL (after DNS + certbot)"
  value       = "https://${var.admin_domain}"
}

output "post_deploy" {
  description = "Steps after terraform apply"
  value       = <<-EOT

    === POST-DEPLOY ===
    1. Esperar 3-5 min para que user-data termine
    2. Abrir: http://${aws_eip.openclaw.public_ip}
    3. Login: admin / OpenClaw2026!
    4. DNS: Agregar A record ${var.admin_domain} -> ${aws_eip.openclaw.public_ip}
    5. En el terminal web: sudo certbot --nginx -d ${var.admin_domain} --non-interactive --agree-tos -m tu@email.com
    6. Acceder: https://${var.admin_domain}
  EOT
}
