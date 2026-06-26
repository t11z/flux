output "device_group" {
  value       = panos_device_group.dg.name
  description = "The device group holding the published apps and NAT rules."
}

output "template_zone" {
  value       = module.template_network.zone_name
  description = "Zone defined in the template and consumed by the device-group rules."
}

output "published_apps" {
  value       = { for k, m in module.app_publish : k => m.address_names }
  description = "Per-app (desired/apps/<name>) created backend address objects."
}

output "nat_rules" {
  value       = keys(module.nat_interplay)
  description = "NAT rules converged from desired/nat/<name>."
}
