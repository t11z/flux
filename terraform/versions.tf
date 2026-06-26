terraform {
  required_version = ">= 1.5"

  # Persistent, authoritative state lives in GitLab-managed Terraform state (HTTP
  # backend). Partial config: address + auth are supplied at `init` via
  # -backend-config (CI uses $CI_JOB_TOKEN). Local validate uses `init -backend=false`.
  # See docs/decisions/0006-* and examples/gitlab/STATE-MANAGEMENT.md.
  backend "http" {}

  required_providers {
    panos = {
      source = "PaloAltoNetworks/panos"
      # The official PAN-OS provider v2 speaks the XML-API (multi-config) - see
      # docs/decisions/0005-use-the-panos-terraform-provider-v2.md.
      version = "~> 2.0"
    }
  }
}
