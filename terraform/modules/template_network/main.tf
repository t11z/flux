# UC2 - "onboard network config in a template": a layer3 ethernet interface, a zone
# bound to it, and a virtual router - all inside a template, bundled into a stack.
# The template layer (network/device config) as opposed to the device-group object layer.

resource "panos_template" "tpl" {
  location    = { panorama = {} }
  name        = var.template
  description = "flux demo template"
}

resource "panos_ethernet_interface" "eth" {
  location = { template = { name = panos_template.tpl.name } }
  name     = var.interface_name
  comment  = "flux demo interface"

  layer3 = {
    ips = [{ name = var.interface_ip }]
  }
}

resource "panos_virtual_router" "vr" {
  location   = { template = { name = panos_template.tpl.name } }
  name       = var.virtual_router
  interfaces = [panos_ethernet_interface.eth.name]
}

resource "panos_zone" "zone" {
  location = { template = { name = panos_template.tpl.name, vsys = var.vsys } }
  name     = var.zone_name

  network = {
    layer3 = [panos_ethernet_interface.eth.name]
  }
}

resource "panos_template_stack" "stack" {
  location = { panorama = {} }
  name     = var.template_stack
  # default_vsys makes the provider emit the <settings> element PAN-OS requires
  # for a stack at commit time (validate-full rejects a stack without it).
  default_vsys = var.vsys
  templates    = [panos_template.tpl.name]
  # The stack's default-vsys references vsys1, which only exists once the zone (in
  # vsys1) is created. Without this dependency Terraform may create the stack first
  # and PAN-OS rejects "default-vsys 'vsys1' is not a valid reference".
  depends_on = [panos_zone.zone]
}
