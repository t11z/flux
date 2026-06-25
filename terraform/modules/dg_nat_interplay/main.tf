# UC3 - "the interplay": a device-group NAT rule whose zones and translation interface
# come from the template (UC2). Source NAT (dynamic-ip-and-port) hiding outbound traffic
# behind the template's interface. This is where the device-group and template layers meet:
# the rule only resolves because the device group binds the template stack (see ../../main.tf).

resource "panos_nat_policy_rules" "nat" {
  location = { device_group = { name = var.device_group } }
  position = { where = "last" }

  rules = [{
    name                  = var.nat_rule_name
    source_zones          = var.source_zones
    destination_zone      = var.destination_zone
    source_addresses      = ["any"]
    destination_addresses = ["any"]
    service               = "any"
    nat_type              = "ipv4"

    source_translation = {
      dynamic_ip_and_port = {
        interface_address = {
          interface = var.translation_interface
        }
      }
    }
  }]
}
