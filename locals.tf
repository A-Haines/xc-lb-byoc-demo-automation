locals {
  cert_name = var.certificate_name != "" ? var.certificate_name : "${var.name_prefix}-cert"

  names = {
    waf         = "${var.name_prefix}-waf"
    svc_policy  = "${var.name_prefix}-svc-policy"
    hc          = "${var.name_prefix}-hc"
    pool        = "${var.name_prefix}-pool"
    lb          = "${var.name_prefix}-lb"
  }

  # All TLS material comes from a single local folder, by convention.
  cert_file      = "${var.cert_dir}/cert.pem"
  chain_file     = "${var.cert_dir}/chain.pem"
  key_file       = "${var.cert_dir}/key.pem"
  blindfold_file = "${var.cert_dir}/key.blindfold"

  cert_pem  = fileexists(local.cert_file) ? file(local.cert_file) : ""
  chain_pem = fileexists(local.chain_file) ? file(local.chain_file) : ""
  key_pem   = fileexists(local.key_file) ? file(local.key_file) : ""

  # key.blindfold holds the offline-encrypted key location (e.g. string:///<blob>).
  # trimspace drops the trailing newline a file write usually leaves behind.
  blindfold_key_location = fileexists(local.blindfold_file) ? trimspace(file(local.blindfold_file)) : ""

  # Certificate material sent to F5XC: leaf, with any intermediate chain appended.
  # Sectigo and most public CAs require the intermediate chain to be served.
  cert_full_pem = local.chain_pem != "" ? "${local.cert_pem}\n${local.chain_pem}" : local.cert_pem

  cert_ref_name      = local.cert_name
  cert_ref_namespace = var.certificate_namespace

  waf_ref_namespace = var.waf_namespace
}
