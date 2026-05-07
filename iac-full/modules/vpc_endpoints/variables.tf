variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "app_subnet_ids" { type = list(string) }
variable "vpc_endpoint_sg_id" { type = string }
