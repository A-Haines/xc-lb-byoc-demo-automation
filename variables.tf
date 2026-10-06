variable "app_namespace" {
  description = "Existing F5XC namespace for healthcheck, origin pool, and load balancer."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for all created resource names."
  type        = string
  default     = "epsilon"
}

variable "domains" {
  description = "Domains served by the HTTPS load balancer."
  type        = list(string)
  validation {
    condition     = length(var.domains) > 0
    error_message = "At least one domain is required."
  }
}

variable "origin_servers" {
  description = "Origin servers. Each entry: type = \"dns\" or \"ip\", value = hostname or IP."
  type = list(object({
    type  = string
    value = string
  }))
  validation {
    condition     = length(var.origin_servers) > 0
    error_message = "At least one origin server is required."
  }
  validation {
    condition     = alltrue([for s in var.origin_servers : contains(["dns", "ip"], s.type)])
    error_message = "Each origin_servers entry type must be \"dns\" or \"ip\"."
  }
}

variable "origin_port" {
  description = "TCP port on the origin servers."
  type        = number
  default     = 80
}

variable "origin_use_tls" {
  description = "If true, connect to origins over TLS."
  type        = bool
  default     = false
}

variable "origin_tls_skip_verification" {
  description = "If true (and origin_use_tls), skip origin server certificate verification. Insecure; default verifies against the Volterra trusted CA bundle."
  type        = bool
  default     = false
}

variable "health_check_path" {
  description = "HTTP path for the health check."
  type        = string
  default     = "/"
}

variable "health_check_status_codes" {
  description = "Expected HTTP status codes for the health check."
  type        = list(string)
  default     = ["200"]
}

variable "healthy_threshold" {
  description = "Consecutive successes to mark an origin healthy."
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Consecutive failures to mark an origin unhealthy."
  type        = number
  default     = 3
}

variable "health_interval" {
  description = "Seconds between health check probes."
  type        = number
  default     = 10
}

variable "health_timeout" {
  description = "Seconds before a health check probe is a failure."
  type        = number
  default     = 3
}

variable "waf_enforcement" {
  description = "App firewall mode: blocking or monitoring."
  type        = string
  default     = "blocking"
  validation {
    condition     = contains(["blocking", "monitoring"], var.waf_enforcement)
    error_message = "waf_enforcement must be \"blocking\" or \"monitoring\"."
  }
}

variable "service_policy_action" {
  description = "Service policy default action: allow_all or deny_all."
  type        = string
  default     = "allow_all"
  validation {
    condition     = contains(["allow_all", "deny_all"], var.service_policy_action)
    error_message = "service_policy_action must be \"allow_all\" or \"deny_all\"."
  }
}

variable "advertise_mode" {
  description = "LB advertisement: public_default_vip, public_ip, or do_not_advertise."
  type        = string
  default     = "public_default_vip"
  validation {
    condition     = contains(["public_default_vip", "public_ip", "do_not_advertise"], var.advertise_mode)
    error_message = "advertise_mode must be public_default_vip, public_ip, or do_not_advertise."
  }
}

variable "enable_http_redirect" {
  description = "Redirect HTTP to HTTPS on the load balancer."
  type        = bool
  default     = true
}

variable "enable_hsts" {
  description = "Add HSTS header on the load balancer."
  type        = bool
  default     = true
}

variable "certificate_mode" {
  description = "How the TLS certificate is supplied: clear, blindfold, vault, or existing."
  type        = string
  default     = "clear"
  validation {
    condition     = contains(["clear", "blindfold", "vault", "existing"], var.certificate_mode)
    error_message = "certificate_mode must be clear, blindfold, vault, or existing."
  }
}

variable "certificate_name" {
  description = "Name of the created certificate (defaults to \"<name_prefix>-cert\" when empty)."
  type        = string
  default     = ""
}

variable "certificate_namespace" {
  description = "Namespace for the created certificate."
  type        = string
  default     = "shared"
}

variable "certificate_pem" {
  description = "Certificate PEM (inline). Used by clear/blindfold modes if certificate_file is empty."
  type        = string
  default     = ""
  sensitive   = true
}

variable "private_key_pem" {
  description = "Private key PEM (inline, unencrypted). Used by clear mode if private_key_file is empty."
  type        = string
  default     = ""
  sensitive   = true
}

variable "certificate_chain_pem" {
  description = "Optional intermediate certificate chain PEM (inline)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "certificate_file" {
  description = "Path to a certificate PEM file (alternative to certificate_pem)."
  type        = string
  default     = ""
}

variable "private_key_file" {
  description = "Path to a private key PEM file (alternative to private_key_pem)."
  type        = string
  default     = ""
}

variable "blindfold_key_location" {
  description = "Blindfolded private key location, e.g. string:///<blindfolded>. Used by blindfold mode."
  type        = string
  default     = ""
}

variable "vault_key_location" {
  description = "Path to the key secret in Vault. Used by vault mode (provider-deprecated)."
  type        = string
  default     = ""
}

variable "vault_provider" {
  description = "Secret Management Access object name backing Vault. Used by vault mode."
  type        = string
  default     = ""
}

variable "vault_key" {
  description = "Optional specific key within the Vault secret."
  type        = string
  default     = ""
}

variable "existing_certificate_name" {
  description = "Name of a pre-existing certificate to reference. Used by existing mode."
  type        = string
  default     = ""
}

variable "existing_certificate_namespace" {
  description = "Namespace of the pre-existing certificate. Used by existing mode."
  type        = string
  default     = "shared"
}
