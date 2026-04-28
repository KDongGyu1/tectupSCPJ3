variable "name_prefix" { type = string }
variable "vpc_cidr" { type = string }
variable "az_names" { type = list(string) }
variable "public_subnet_cidrs" { type = list(string) }
variable "app_subnet_cidrs" { type = list(string) }
variable "db_subnet_cidrs" { type = list(string) }
