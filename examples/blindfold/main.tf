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
variable "blindfold_key_location" { type = string }

module "app_delivery" {
  source = "../.."

  app_namespace = "my-app-ns"
  domains       = ["www.example.com"]

  origin_servers = [
    { type = "dns", value = "origin.example.com" },
  ]

  certificate_mode       = "blindfold"
  certificate_pem        = var.certificate_pem
  blindfold_key_location = var.blindfold_key_location
}

output "load_balancer_domains" {
  value = module.app_delivery.load_balancer_domains
}
