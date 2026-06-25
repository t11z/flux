variable "device_group" {
  type        = string
  description = "Device group holding the NAT rule."
}

variable "nat_rule_name" {
  type        = string
  description = "Name of the NAT rule."
}

variable "source_zones" {
  type        = list(string)
  description = "Source zones (from the template) the rule matches."
}

variable "destination_zone" {
  type        = list(string)
  description = "Destination zone (from the template); must not be 'any' for NAT."
}

variable "translation_interface" {
  type        = string
  description = "Template interface to hide source traffic behind (DIPP)."
}
