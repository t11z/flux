variable "template" {
  type        = string
  description = "Template to create and hold the network config."
}

variable "template_stack" {
  type        = string
  description = "Template stack bundling the template."
}

variable "vsys" {
  type        = string
  default     = "vsys1"
  description = "vsys the zone lives in."
}

variable "interface_name" {
  type        = string
  description = "Ethernet interface, e.g. ethernet1/1."
}

variable "interface_ip" {
  type        = string
  description = "Interface IP in ip/prefix form."
}

variable "zone_name" {
  type        = string
  description = "Security zone bound to the interface."
}

variable "virtual_router" {
  type        = string
  description = "Virtual router the interface is attached to."
}
