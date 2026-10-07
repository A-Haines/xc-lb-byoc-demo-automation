# Preconditions: fail early if required files are missing for the chosen mode
locals {
  _validate_clear = var.certificate_mode == "clear" && local.key_pem == "" ? tobool(
    "certificate_mode=clear requires ${var.cert_dir}/key.pem to exist"
  ) : true

  _validate_blindfold = var.certificate_mode == "blindfold" && local.blindfold_key_location == "" ? tobool(
    "certificate_mode=blindfold requires ${var.cert_dir}/key.blindfold to exist. Create it with: vesctl request secrets encrypt --policy-document policy --public-key pubkey key.pem | tail -1 > key.blindfold"
  ) : true
}

resource "volterra_certificate" "this" {
  name      = local.cert_name
  namespace = var.certificate_namespace

  certificate_url = "string:///${base64encode(local.cert_full_pem)}"

  private_key {
    dynamic "clear_secret_info" {
      for_each = var.certificate_mode == "clear" ? [1] : []
      content {
        url = "string:///${base64encode(local.key_pem)}"
      }
    }

    dynamic "blindfold_secret_info" {
      for_each = var.certificate_mode == "blindfold" ? [1] : []
      content {
        location = "string:///${local.blindfold_key_location}"
      }
    }
  }
}
