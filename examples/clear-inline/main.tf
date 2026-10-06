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
  # P12 password comes from the VES_P12_PASSWORD environment variable.
}

variable "api_p12_file" { type = string }
variable "api_url" { type = string }
variable "certificate_pem" {
  type      = string
  sensitive = true
}
variable "private_key_pem" {
  type      = string
  sensitive = true
}

module "app_delivery" {
  source = "../.."

  app_namespace = "my-app-ns"
  domains       = ["www.example.com"]

  origin_servers = [
    { type = "dns", value = "origin.example.com" },
  ]

  certificate_mode = "clear"
  certificate_pem  = var.certificate_pem
  private_key_pem  = var.private_key_pem
}

output "load_balancer_domains" {
  value = module.app_delivery.load_balancer_domains
}
