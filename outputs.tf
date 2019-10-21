output "frontend-dns" {
  value = module.instance-frontend.public_dns
}
output "frontend-ip" {
  value = module.instance-frontend.public_ip
}
