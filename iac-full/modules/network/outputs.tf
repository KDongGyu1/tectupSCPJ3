output "vpc_id" { value = aws_vpc.main.id }
output "vpc_cidr" { value = aws_vpc.main.cidr_block }
output "public_subnet_ids" { value = [for subnet in aws_subnet.public : subnet.id] }
output "app_subnet_ids" { value = [for subnet in aws_subnet.app : subnet.id] }
output "db_subnet_ids" { value = [for subnet in aws_subnet.db : subnet.id] }
output "public_route_table_id" { value = aws_route_table.public.id }
output "app_route_table_ids" { value = [for rt in aws_route_table.app : rt.id] }
output "db_route_table_id" { value = aws_route_table.db.id }
