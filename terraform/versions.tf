terraform {
  required_version = ">= 1.5"
  required_providers {
    panos = {
      source = "PaloAltoNetworks/panos"
      # The official PAN-OS provider v2 speaks the XML-API (multi-config) - see
      # docs/decisions/0005-use-the-panos-terraform-provider-v2.md.
      version = "~> 2.0"
    }
  }
}
