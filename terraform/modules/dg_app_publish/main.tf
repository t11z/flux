# UC1 - "publish an application": create the backend address objects, bundle them in
# an address group, define the service port, and allow it with one security rule.
# Everyday device-group object/policy work.

resource "panos_address" "srv" {
  for_each = var.server_ips

  location    = { device_group = { name = var.device_group } }
  name        = each.key
  ip_netmask  = each.value
  description = "flux: ${var.app_name} backend"
}

resource "panos_address_group" "grp" {
  location = { device_group = { name = var.device_group } }
  name     = "${var.app_name}-servers"
  static   = [for a in panos_address.srv : a.name]
}

resource "panos_service" "svc" {
  location = { device_group = { name = var.device_group } }
  name     = "${var.app_name}-tcp-${var.service_port}"
  protocol = { tcp = { destination_port = var.service_port } }
}

resource "panos_security_policy_rules" "allow" {
  location = { device_group = { name = var.device_group } }
  position = { where = "last" }

  rules = [{
    name                  = "${var.app_name}-allow"
    source_zones          = var.source_zones
    destination_zones     = var.destination_zones
    source_addresses      = ["any"]
    destination_addresses = [panos_address_group.grp.name]
    applications          = var.applications
    services              = [panos_service.svc.name]
    action                = "allow"
    log_end               = true
  }]
}
