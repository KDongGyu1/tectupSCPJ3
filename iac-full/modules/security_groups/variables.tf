variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "vpc_cidr" { type = string }
variable "allowed_http_cidr_blocks" { type = list(string) }
