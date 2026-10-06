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

module "app_delivery" {
  source = "../.."

  app_namespace = "my-app-ns"
  domains       = ["www.example.com"]

  origin_servers = [
    { type = "ip", value = "203.0.113.10" },
  ]

  certificate_mode = "clear"
  certificate_file = "${path.module}/cert.pem"
  private_key_file = "${path.module}/key.pem"
}

output "load_balancer_domains" {
  value = module.app_delivery.load_balancer_domains
}
