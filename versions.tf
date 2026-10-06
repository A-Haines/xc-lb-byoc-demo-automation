terraform {
  required_version = ">= 1.7"

  required_providers {
    volterra = {
      source  = "volterraedge/volterra"
      version = "~> 0.13"
    }
  }
}
