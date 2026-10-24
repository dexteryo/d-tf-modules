output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block"
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "Zones the subnets are in, in the order of the subnet ID lists"
  value       = var.availability_zones
}

output "public_subnet_ids" {
  description = "Public subnets that hold the NAT gateways, one per zone"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnets with a route out through the NAT gateway of their zone, one per zone"
  value       = aws_subnet.private[*].id
}

output "isolated_subnet_ids" {
  description = "Subnets with no route out, for databases, one per zone"
  value       = aws_subnet.isolated[*].id
}

output "nat_eips" {
  description = "Elastic IPs of the NAT gateways, one per zone; give these to partners that keep an allow-list"
  value       = aws_eip.nat[*].public_ip
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs, one per zone"
  value       = aws_nat_gateway.this[*].id
}

output "public_route_table_id" {
  description = "Route table shared by the public subnets"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "Route tables of the private subnets, one per zone"
  value       = aws_route_table.private[*].id
}

output "isolated_route_table_id" {
  description = "Route table shared by the isolated subnets"
  value       = aws_route_table.isolated.id
}

output "endpoints_security_group_id" {
  description = "Security group of the interface endpoints"
  value       = aws_security_group.endpoints.id
}

output "flow_log_group_arn" {
  description = "Log group that receives the VPC flow logs"
  value       = aws_cloudwatch_log_group.flow.arn
}
