# flux - converge the FULL managed Panorama config from git desired-state.
#
# One coherent state = one consistent Panorama config (the device is configured
# EXCLUSIVELY through flux). Desired state lives in terraform/desired/ as data
# records; this root composes the coupled template + device-group scaffolding
# (singletons - the two-dimensional Template<->Device-Group interplay) and
# for_each-es the published apps and NAT rules over their records. Adding,
# editing, or removing a record touches ONLY that object - no sibling churn.
# See docs/decisions/0006-authoritative-persistent-state.md.

locals {
  network = yamldecode(file("${path.module}/desired/network.yaml"))
  apps = {
    for f in fileset("${path.module}/desired/apps", "*.yaml") :
    trimsuffix(f, ".yaml") => yamldecode(file("${path.module}/desired/apps/${f}"))
  }
  nat_rules = {
    for f in fileset("${path.module}/desired/nat", "*.yaml") :
    trimsuffix(f, ".yaml") => yamldecode(file("${path.module}/desired/nat/${f}"))
  }
}

# ---- template network config (interface + zone + virtual router) ----
# Built first: it owns the template + stack that the device-group binds to and that
# the NAT rules reference -> the device-group <-> template interplay.
module "template_network" {
  source = "./modules/template_network"

  template       = local.network.template
  template_stack = local.network.template_stack
  vsys           = local.network.vsys
  interface_name = local.network.interface_name
  interface_ip   = local.network.interface_ip
  zone_name      = local.network.zone_name
  virtual_router = local.network.virtual_router
}

# The device-group binds the template stack (so its rules can resolve the template's
# zones/interfaces) - the structural link between the two Panorama layers.
resource "panos_device_group" "dg" {
  location  = { panorama = {} }
  name      = local.network.device_group
  templates = [module.template_network.template_stack_name]
}

# ---- published applications: one module instance per desired/apps/<name>.yaml ----
module "app_publish" {
  for_each = local.apps
  source   = "./modules/dg_app_publish"

  device_group      = panos_device_group.dg.name
  app_name          = each.value.app_name
  server_ips        = each.value.server_ips
  service_port      = each.value.service_port
  source_zones      = each.value.source_zones
  destination_zones = [module.template_network.zone_name]
  applications      = each.value.applications
}

# ---- NAT rules: one module instance per desired/nat/<name>.yaml (template<->DG interplay) ----
module "nat_interplay" {
  for_each = local.nat_rules
  source   = "./modules/dg_nat_interplay"

  device_group          = panos_device_group.dg.name
  nat_rule_name         = each.value.nat_rule_name
  source_zones          = [module.template_network.zone_name]
  destination_zone      = [module.template_network.zone_name]
  translation_interface = module.template_network.interface_name
}
