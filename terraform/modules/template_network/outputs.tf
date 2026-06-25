output "template_name" {
  value = panos_template.tpl.name
}

output "template_stack_name" {
  value = panos_template_stack.stack.name
}

output "interface_name" {
  value = panos_ethernet_interface.eth.name
}

output "zone_name" {
  value = panos_zone.zone.name
}

output "virtual_router_name" {
  value = panos_virtual_router.vr.name
}
