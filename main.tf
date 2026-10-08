#############################################
# Shared namespace: App Firewall & Service Policy
#############################################

resource "volterra_app_firewall" "this" {
  name      = local.names.waf
  # namespace = var.waf_namespace
  namespace = local.waf_ref_namespace


  allow_all_response_codes   = true
  disable_anonymization      = true
  use_default_blocking_page  = true
  default_detection_settings = true

  enable_ai_enhancements {
    mitigate_high_medium_risk_action = true
  }

  blocking   = var.waf_enforcement == "blocking" ? true : null
  monitoring = var.waf_enforcement == "monitoring" ? true : null
}

# Service policy is OPTIONAL - tenant may have hit 550 policy limit.
# Set var.service_policy_name to an existing policy name, or leave empty to skip.

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
    for_each = toset([var.origin_servers])
    content {
      public_name {
        dns_name = origin_servers.value
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
      # Verify the origin certificate by default; skipping is an explicit opt-in.
      skip_server_verification = var.origin_tls_skip_verification ? true : null
      volterra_trusted_ca      = var.origin_tls_skip_verification ? null : true
      use_host_header_as_sni   = true
      tls_config {
        default_security = true
      }
    }
  }
}

#############################################
# App namespace: HTTPS Load Balancer
#############################################

resource "volterra_http_loadbalancer" "this" {
  name      = local.names.lb
  namespace = var.app_namespace
  domains   = [var.domains]

  https {
    port          = 443
    http_redirect = var.enable_http_redirect
    add_hsts      = var.enable_hsts
    # Normalize request paths before WAF/service-policy evaluation so that
    # path-traversal encodings (e.g. /app/../admin) cannot bypass them.
    enable_path_normalize = true

    tls_cert_params {
      no_mtls = true
      certificates {
        name      = local.cert_ref_name
        namespace = local.cert_ref_namespace
      }
      tls_config {
        default_security = true
      }
    }
  }

  app_firewall {
    name      = volterra_app_firewall.this.name
    namespace = local.waf_ref_namespace
  }

  # Service policy: use existing if specified, otherwise skip (no_service_policies)
  dynamic "active_service_policies" {
    for_each = var.service_policy_name != "" ? [1] : []
    content {
      policies {
        name      = var.service_policy_name
        namespace = "shared"
      }
    }
  }
  no_service_policies = var.service_policy_name == "" ? true : null

  default_route_pools {
    pool {
      name      = volterra_origin_pool.this.name
      namespace = var.app_namespace
    }
    weight = 1
  }

  # Advertisement (one of the required oneof)
  advertise_on_public_default_vip = var.advertise_mode == "public_default_vip" ? true : null
  do_not_advertise                = var.advertise_mode == "do_not_advertise" ? true : null
  dynamic "advertise_on_public" {
    for_each = var.advertise_mode == "public_ip" ? [1] : []
    content {
      public_ip {
        name      = "${var.name_prefix}-public-ip"
        namespace = "shared"
      }
    }
  }

  # Required oneof selectors — safe minimal defaults
  no_challenge                     = true
  round_robin                      = true
  disable_api_definition           = true
  disable_api_discovery            = true
  disable_api_testing              = true
  disable_malicious_user_detection = true
  disable_malware_protection       = true
  disable_rate_limit               = true
  default_sensitive_data_policy    = true
  disable_threat_mesh              = true
  disable_trust_client_ip_headers  = true
  user_id_client_ip                = true

  depends_on = [volterra_certificate.this]
}
