locals {
  cert_name = var.certificate_name != "" ? var.certificate_name : "${var.name_prefix}-cert"

  names = {
    waf  = "${var.name_prefix}-waf"
    svc  = "${var.name_prefix}-svc-policy"
    hc   = "${var.name_prefix}-hc"
    pool = "${var.name_prefix}-pool"
    lb   = "${var.name_prefix}-lb"
  }

  # Inline PEM takes precedence over file paths; empty string means "not provided".
  cert_pem = var.certificate_pem != "" ? var.certificate_pem : (
    var.certificate_file != "" ? file(var.certificate_file) : ""
  )
  key_pem = var.private_key_pem != "" ? var.private_key_pem : (
    var.private_key_file != "" ? file(var.private_key_file) : ""
  )
  chain_pem = var.certificate_chain_pem

  # Certificate material sent to F5XC: leaf, with any intermediate chain appended.
  # Sectigo and most public CAs require the intermediate chain to be served.
  cert_full_pem = local.chain_pem != "" ? "${local.cert_pem}\n${local.chain_pem}" : local.cert_pem

  create_certificate = var.certificate_mode != "existing"

  cert_ref_name      = var.certificate_mode == "existing" ? var.existing_certificate_name : local.cert_name
  cert_ref_namespace = var.certificate_mode == "existing" ? var.existing_certificate_namespace : var.certificate_namespace
}
