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
variable "certificate_pem" {
  type      = string
  sensitive = true
}

# NOTE: vault_secret_info is marked DEPRECATED in the volterra provider.
# Prefer clear or blindfold for new deployments.
module "app_delivery" {
  source = "../.."

  app_namespace = "my-app-ns"
  domains       = ["www.example.com"]

  origin_servers = [
    { type = "dns", value = "origin.example.com" },
  ]

  certificate_mode   = "vault"
  certificate_pem    = var.certificate_pem
  vault_key_location = "secret/data/tls/www-example-com"
  vault_provider     = "my-vault-sma"
}

output "load_balancer_domains" {
  value = module.app_delivery.load_balancer_domains
}
