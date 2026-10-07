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

module "app_delivery" {
  source = "../.."

  app_namespace = "my-app-ns"
  domains       = ["www.example.com"]

  origin_servers = ["origin.example.com"]

  # Point at a local folder holding cert.pem + key.blindfold (and optional chain.pem).
  certificate_mode = "blindfold"
  cert_dir         = "${path.module}/certs"
}

output "load_balancer_domains" {
  value = module.app_delivery.load_balancer_domains
}
