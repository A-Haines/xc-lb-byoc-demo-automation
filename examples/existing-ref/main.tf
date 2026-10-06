terraform {
  required_version = ">= 1.7"
  required_providers {
    volterra = {
      source  = "volterraedge/volterra"
      version = "~> 0.13"
    }
  }
}

provider "volterra" {
  api_p12_file = var.api_p12_file
  url          = var.api_url
}

variable "api_p12_file" { type = string }
variable "api_url" { type = string }

# Use this mode when the certificate is managed outside Terraform:
# a pre-uploaded custom cert, OR an XC-managed certificate issued via the
# Sectigo CA -> Venafi -> F5 Distributed Cloud integration (see
# scripts/xc-managed-cert.md). Terraform only references it by name.
module "app_delivery" {
  source = "../.."

  app_namespace = "my-app-ns"
  domains       = ["www.example.com"]

  origin_servers = [
    { type = "dns", value = "origin.example.com" },
  ]

  certificate_mode               = "existing"
  existing_certificate_name      = "www-example-com"
  existing_certificate_namespace = "shared"
}

output "load_balancer_domains" {
  value = module.app_delivery.load_balancer_domains
}
