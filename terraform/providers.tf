# The provider targets a Panorama over the XML-API. Point it at a real Panorama
# (https) or at the flux mock (http) via *.tfvars - the resource graph is identical.
provider "panos" {
  hostname = var.panos_hostname
  protocol = var.panos_protocol
  port     = var.panos_port

  # Supply EITHER api_key OR username+password (unused ones stay null).
  api_key  = var.panos_api_key
  username = var.panos_username
  password = var.panos_password

  skip_verify_certificate = var.panos_skip_verify_certificate
}
