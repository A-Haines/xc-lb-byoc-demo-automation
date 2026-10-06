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

#############################################
# App namespace: Health Check & Origin Pool
#############################################

resource "volterra_healthcheck" "this" {
  name      = local.names.hc
  namespace = var.app_namespace

  http_health_check {
    path                   = var.health_check_path
    use_origin_server_name = true
    expected_status_codes  = var.health_check_status_codes
  }

  healthy_threshold   = var.healthy_threshold
  unhealthy_threshold = var.unhealthy_threshold
  interval            = var.health_interval
  timeout             = var.health_timeout
}

resource "volterra_origin_pool" "this" {
  name      = local.names.pool
  namespace = var.app_namespace

  # Provider v0.13.2: endpoint_selection / loadbalancer_algorithm are scalar strings.
  endpoint_selection     = "LOCAL_PREFERRED"
  loadbalancer_algorithm = "ROUND_ROBIN"
  port                   = var.origin_port

  dynamic "origin_servers" {
    for_each = var.origin_servers
    content {
      dynamic "public_name" {
        for_each = origin_servers.value.type == "dns" ? [1] : []
        content {
          dns_name = origin_servers.value.value
        }
      }
      dynamic "public_ip" {
        for_each = origin_servers.value.type == "ip" ? [1] : []
        content {
          ip = origin_servers.value.value
        }
      }
    }
  }

  healthcheck {
    name      = volterra_healthcheck.this.name
    namespace = var.app_namespace
  }

  no_tls = var.origin_use_tls ? null : true

  dynamic "use_tls" {
    for_each = var.origin_use_tls ? [1] : []
    content {
      default_session_key_caching = true
      no_mtls                     = true
      skip_server_verification    = true
      use_host_header_as_sni      = true
      tls_config {
        default_security = true
      }
    }
  }
}
