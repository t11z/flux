# flux Phase 3 - three everyday firewall-admin use cases against Panorama, driven
# through the official panos v2 provider (XML-API). The three modules are
# independently reusable; this root config composes them into one coherent change.

# ---- UC2: template network config (interface + zone + virtual router) ----
# Built first: it owns the template + stack that the device-group binds to and that
# the NAT rule (UC3) references -> this is the device-group <-> template interplay.
module "template_network" {
  source = "./modules/template_network"

  template       = var.template
  template_stack = var.template_stack
  vsys           = var.vsys
  interface_name = var.interface_name
  interface_ip   = var.interface_ip
  zone_name      = var.zone_name
  virtual_router = var.virtual_router
}

# The device-group binds the template stack (so its rules can resolve the template's
# zones/interfaces) - the structural link between the two Panorama layers.
resource "panos_device_group" "dg" {
  location  = { panorama = {} }
  name      = var.device_group
  templates = [module.template_network.template_stack_name]
}

# ---- UC1: publish an application (address objects + service + security rule) ----
module "app_publish" {
  source = "./modules/dg_app_publish"

  device_group      = panos_device_group.dg.name
  app_name          = var.app_name
  server_ips        = var.server_ips
  service_port      = var.service_port
  source_zones      = var.app_source_zones
  destination_zones = [module.template_network.zone_name]
  applications      = var.app_applications
}

# ---- UC3: NAT rule referencing the template's zone + interface (the interplay) ----
module "nat_interplay" {
  source = "./modules/dg_nat_interplay"

  device_group          = panos_device_group.dg.name
  nat_rule_name         = var.nat_rule_name
  source_zones          = [module.template_network.zone_name]
  destination_zone      = [module.template_network.zone_name]
  translation_interface = module.template_network.interface_name
}
