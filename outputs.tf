output "load_balancer_name" {
  description = "Name of the HTTPS load balancer."
  value       = volterra_http_loadbalancer.this.name
}

output "load_balancer_domains" {
  description = "Domains served by the load balancer."
  value       = volterra_http_loadbalancer.this.domains
}

output "certificate_id" {
  description = "ID of the created certificate (null when certificate_mode=existing)."
  value       = local.create_certificate ? volterra_certificate.this[0].id : null
}

output "certificate_reference" {
  description = "Name/namespace the load balancer uses for its TLS certificate."
  value = {
    name      = local.cert_ref_name
    namespace = local.cert_ref_namespace
  }
}

output "origin_pool_name" {
  description = "Name of the origin pool."
  value       = volterra_origin_pool.this.name
}

output "app_firewall_name" {
  description = "Name of the app firewall (shared namespace)."
  value       = volterra_app_firewall.this.name
}

output "service_policy_name" {
  description = "Name of the service policy (shared namespace)."
  value       = volterra_service_policy.this.name
}
