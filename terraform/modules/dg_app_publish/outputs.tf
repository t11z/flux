output "address_names" {
  value       = [for a in panos_address.srv : a.name]
  description = "Created backend address objects."
}

output "address_group_name" {
  value = panos_address_group.grp.name
}

output "service_name" {
  value = panos_service.svc.name
}
