output "elastic_ip" {
  description = "Public Elastic IP of the OpenClaw server"
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

output "openclaw_url" {
  description = "OpenClaw gateway URL"
  value       = "http://${aws_eip.openclaw.public_ip}:18789"
}
