output "device_group" {
  value       = one(panos_device_group.dg[*].name)
  description = "The device group holding the published app and NAT rule (null if not in this run)."
}

output "template_zone" {
  value       = one(module.template_network[*].zone_name)
  description = "Zone defined in the template and consumed by the NAT rule (null if not in this run)."
}

output "published_app_addresses" {
  value       = try(one(module.app_publish[*].address_names), [])
  description = "Address objects created for the published application (empty if not in this run)."
}
