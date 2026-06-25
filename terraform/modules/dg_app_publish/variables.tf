variable "device_group" {
  type        = string
  description = "Target device group."
}

variable "app_name" {
  type        = string
  description = "Logical app name; used as a prefix for the created objects."
}

variable "server_ips" {
  type        = map(string)
  description = "Backend servers to publish (object name => ip-netmask)."
}

variable "service_port" {
  type        = string
  description = "TCP destination port to open."
}

variable "source_zones" {
  type        = list(string)
  description = "Zones traffic is allowed from."
}

variable "destination_zones" {
  type        = list(string)
  description = "Zones the servers live in."
}

variable "applications" {
  type        = list(string)
  description = "App-IDs permitted by the rule."
}
