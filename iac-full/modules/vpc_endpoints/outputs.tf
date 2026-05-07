output "interface_vpc_endpoint_ids" {
  value = { for name, endpoint in aws_vpc_endpoint.interface : name => endpoint.id }
}
