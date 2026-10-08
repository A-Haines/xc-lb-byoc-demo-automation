#--- F5 XC API auth ------------------------------------------------------------

variable "xc_api_p12_file" {
  description = "Path to the F5 XC API P12 certificate file"
  type        = string
}

variable "xc_api_url" {
  description = "F5 XC API URL (e.g. https://<tenant>.console.ves.volterra.io/api)"
  type        = string
}

variable "app_namespace" {
  description = "Existing F5XC namespace for healthcheck, origin pool, and load balancer."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for all created resource names."
  type        = string
}

variable "domains" {
  description = "Domain served by the HTTPS load balancer (single string, converted to list internally)."
  type        = string
}

variable "origin_servers" {
  description = "Public DNS name of the origin server (single string, converted to list internally)."
  type        = string
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
variable "waf_namespace" {
  description = "Namespace for the created WAF."
  type        = string
  default     = "shared"

  validation {
    condition     = var.waf_namespace != ""
    error_message = "waf_namespace cannot be empty; the Volterra API requires metadata.namespace."
  }
}
variable "waf_enforcement" {
  description = "App firewall mode: blocking or monitoring."
  type        = string
  default     = "monitoring"
}

variable "service_policy_name" {
  description = "Name of an existing service policy in shared namespace. Leave empty to skip (no_service_policies)."
  type        = string
  default     = ""
}

variable "advertise_mode" {
  description = "LB advertisement: public_default_vip, public_ip, or do_not_advertise."
  type        = string
  default     = "public_default_vip"
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

#############################################
# Certificate: local-folder sourced
#############################################

variable "certificate_mode" {
  description = "How the private key is supplied: \"clear\" (unencrypted key.pem) or \"blindfold\" (offline-encrypted key.blindfold)."
  type        = string
  default     = "clear"

  validation {
    condition     = contains(["clear", "blindfold"], var.certificate_mode)
    error_message = "certificate_mode must be \"clear\" or \"blindfold\"."
  }
}

variable "cert_dir" {
  description = <<-EOT
    Path to a local folder holding the TLS material, by convention:
      cert.pem       leaf certificate (required)
      chain.pem      intermediate chain (optional; appended after the leaf)
      key.pem        unencrypted private key (certificate_mode = "clear")
      key.blindfold  offline-encrypted key location, e.g. string:///<blob> from
                     `vesctl request secrets encrypt` (certificate_mode = "blindfold")
    Pass an absolute path or "$${path.module}/certs" from the calling root.
  EOT
  type        = string
  default = "./certs"
}

variable "certificate_name" {
  description = "Name of the created certificate (defaults to \"<name_prefix>-cert\" when empty)."
  type        = string
  default     = ""
}

variable "certificate_namespace" {
  description = "Namespace for the created certificate."
  type        = string
  # default     = "shared"
}
