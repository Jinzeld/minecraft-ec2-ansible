# terraform/outputs.tf

output "instance_public_ip" {
  description = "Public IP address of the Minecraft EC2 instance"
  value       = aws_instance.minecraft.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.minecraft.id
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${var.key_name}.pem ubuntu@${aws_instance.minecraft.public_ip}"
}

output "nmap_command" {
  description = "nmap command to verify the Minecraft server is running"
  value       = "nmap -sV -Pn -p T:25565 ${aws_instance.minecraft.public_ip}"
}
