output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.this.id
}

output "security_group_arn" {
  description = "ARN of the security group"
  value       = aws_security_group.this.arn
}

output "security_group_name" {
  description = "Name AWS generated from the name prefix"
  value       = aws_security_group.this.name
}

output "ingress_rules" {
  description = "The ingress rules as created, keyed like the input"
  value = {
    for key, rule in aws_vpc_security_group_ingress_rule.this : key => {
      protocol                     = rule.ip_protocol
      from_port                    = rule.from_port
      to_port                      = rule.to_port
      cidr_ipv4                    = rule.cidr_ipv4
      cidr_ipv6                    = rule.cidr_ipv6
      prefix_list_id               = rule.prefix_list_id
      referenced_security_group_id = rule.referenced_security_group_id
    }
  }
}

output "egress_rules" {
  description = "The egress rules as created, keyed like the input"
  value = {
    for key, rule in aws_vpc_security_group_egress_rule.this : key => {
      protocol                     = rule.ip_protocol
      from_port                    = rule.from_port
      to_port                      = rule.to_port
      cidr_ipv4                    = rule.cidr_ipv4
      cidr_ipv6                    = rule.cidr_ipv6
      prefix_list_id               = rule.prefix_list_id
      referenced_security_group_id = rule.referenced_security_group_id
    }
  }
}
