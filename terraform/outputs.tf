output "instance_id" {
  value = aws_instance.minecraft.id
}

output "nmap_command" {
  value = "nmap -sV -Pn -p T:25565 ${aws_instance.minecraft.public_ip}"
}
