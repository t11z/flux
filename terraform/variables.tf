# ---- provider / connection ----
variable "panos_hostname" {
  type        = string
  description = "Panorama hostname/IP (or the flux mock host)."
}

variable "panos_protocol" {
  type        = string
  default     = "https"
  description = "https for a real Panorama, http for the flux mock."
}

variable "panos_port" {
  type        = number
  default     = null
  description = "Override port (e.g. 8080 for the mock); null = protocol default."
}

variable "panos_api_key" {
  type        = string
  default     = null
  sensitive   = true
  description = "API key (alternative to username/password)."
}

variable "panos_username" {
  type        = string
  default     = null
  description = "Username (used with password if no api_key)."
}

variable "panos_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "Password (used with username if no api_key)."
}

variable "panos_skip_verify_certificate" {
  type        = bool
  default     = false
  description = "Skip TLS verification (lab / self-signed Panorama)."
}

# ---- shared scaffolding ----
variable "device_group" {
  type    = string
  default = "flux-dg"
}

variable "template" {
  type    = string
  default = "flux-tpl"
}

variable "template_stack" {
  type    = string
  default = "flux-stack"
}

variable "vsys" {
  type    = string
  default = "vsys1"
}

# ---- UC1: publish an application (device-group objects + security rule) ----
variable "app_name" {
  type    = string
  default = "flux-web"
}

variable "server_ips" {
  type        = map(string)
  default     = { "flux-web-srv-1" = "10.10.10.10/32", "flux-web-srv-2" = "10.10.10.11/32" }
  description = "Backend server objects to publish (name => ip-netmask)."
}

variable "service_port" {
  type    = string
  default = "8080"
}

variable "app_source_zones" {
  type    = list(string)
  default = ["untrust"]
}

variable "app_applications" {
  type    = list(string)
  default = ["web-browsing", "ssl"]
}

# ---- UC2: template network config (interface + zone + virtual router) ----
variable "interface_name" {
  type    = string
  default = "ethernet1/1"
}

variable "interface_ip" {
  type    = string
  default = "10.0.0.1/24"
}

variable "zone_name" {
  type    = string
  default = "flux-trust"
}

variable "virtual_router" {
  type    = string
  default = "flux-vr"
}

# ---- UC3: NAT rule (device-group <-> template interplay) ----
variable "nat_rule_name" {
  type    = string
  default = "flux-nat-hide"
}
