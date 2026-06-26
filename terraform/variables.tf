# ---- provider / connection ----
# Connection config comes from *.tfvars / TF_VAR_* (mock vs real Panorama).
# The DESIRED configuration (template, device-group, apps, NAT rules) is NOT here -
# it lives as data records under terraform/desired/ (the git source of truth).
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
