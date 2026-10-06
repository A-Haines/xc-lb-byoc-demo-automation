#############################################
# Shared namespace: App Firewall & Service Policy
#############################################

resource "volterra_app_firewall" "this" {
  name      = local.names.waf
  namespace = "shared"

  allow_all_response_codes   = true
  disable_anonymization      = true
  use_default_blocking_page  = true
  default_bot_setting        = true
  default_detection_settings = true
  disable_ai_enhancements    = true

  blocking   = var.waf_enforcement == "blocking" ? true : null
  monitoring = var.waf_enforcement == "monitoring" ? true : null
}

resource "volterra_service_policy" "this" {
  name      = local.names.svc
  namespace = "shared"
  algo      = "FIRST_MATCH"

  any_server = true

  allow_all_requests = var.service_policy_action == "allow_all" ? true : null
  deny_all_requests  = var.service_policy_action == "deny_all" ? true : null
}
