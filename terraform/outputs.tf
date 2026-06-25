output "device_group" {
  value       = panos_device_group.dg.name
  description = "The device group holding the published app and NAT rule."
}

output "template_zone" {
  value       = module.template_network.zone_name
  description = "Zone defined in the template and consumed by the NAT rule."
}

output "published_app_addresses" {
  value       = module.app_publish.address_names
  description = "Address objects created for the published application."
}
