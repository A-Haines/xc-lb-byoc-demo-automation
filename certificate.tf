resource "volterra_certificate" "this" {
  count     = local.create_certificate ? 1 : 0
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
        location = var.blindfold_key_location
      }
    }

    dynamic "vault_secret_info" {
      for_each = var.certificate_mode == "vault" ? [1] : []
      content {
        location = var.vault_key_location
        provider = var.vault_provider
        key      = var.vault_key
      }
    }
  }

  lifecycle {
    precondition {
      condition = (
        var.certificate_mode == "clear" ? (local.cert_pem != "" && local.key_pem != "") : (
          var.certificate_mode == "blindfold" ? (local.cert_pem != "" && var.blindfold_key_location != "") : (
            var.certificate_mode == "vault" ? (var.vault_key_location != "" && var.vault_provider != "") : true
          )
        )
      )
      error_message = "Missing inputs for certificate_mode=${var.certificate_mode}: clear needs cert+key material; blindfold needs cert + blindfold_key_location; vault needs vault_key_location + vault_provider."
    }
  }
}
