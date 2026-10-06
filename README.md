# F5 Distributed Cloud App-Delivery Terraform Package

A lean, reusable Terraform module that deploys a complete HTTPS application-delivery
stack in F5 Distributed Cloud (XC) with one `terraform apply`, and lets the customer
choose **how the TLS certificate is supplied** — without editing module code.

## What it deploys

| Resource | Provider resource | Namespace |
|---|---|---|
| App Firewall (WAF) | `volterra_app_firewall` | `shared` |
| Service Policy | `volterra_service_policy` | `shared` |
| Certificate (unless `existing`) | `volterra_certificate` | `shared` (default) |
| HTTP Health Check | `volterra_healthcheck` | `var.app_namespace` |
| Origin Pool | `volterra_origin_pool` | `var.app_namespace` |
| HTTPS Load Balancer | `volterra_http_loadbalancer` | `var.app_namespace` |

The load balancer applies the WAF and service policy from `shared`, routes to the
health-checked origin pool, serves HTTPS with your chosen certificate, and (by default)
redirects HTTP→HTTPS with HSTS enabled.

## Requirements

- Terraform **>= 1.7** (uses native `terraform test` + `mock_provider`).
- Provider `volterraedge/volterra` **~> 0.13** (developed against 0.13.2).
- An existing `shared` namespace (built in) and an existing `var.app_namespace`.
  **This module does not create namespaces.**
- F5XC API credentials (P12 file + URL, or cert/key + URL).

## Certificate modes

Pick one with `certificate_mode`:

| Mode | What it does | Key variables | Example |
|---|---|---|---|
| `clear` | Creates a certificate with an unencrypted key (inline PEM or file). Key lands in TF state. | `certificate_pem`+`private_key_pem`, **or** `certificate_file`+`private_key_file` | [`clear-inline`](examples/clear-inline/), [`clear-file`](examples/clear-file/) |
| `blindfold` | Creates a certificate with a Blindfold-encrypted key (key never plaintext in state). **Recommended.** | `certificate_pem` + `blindfold_key_location` | [`blindfold`](examples/blindfold/) |
| `vault` | Creates a certificate with the key sourced from HashiCorp Vault. *Provider-deprecated.* | `certificate_pem` + `vault_key_location` + `vault_provider` | [`vault`](examples/vault/) |
| `existing` | References a certificate already in the tenant — including an **XC-managed (Sectigo→Venafi→XC)** cert. Creates no certificate. | `existing_certificate_name` + `existing_certificate_namespace` | [`existing-ref`](examples/existing-ref/) |

For the XC-managed (Venafi/Sectigo) path, see
[`scripts/xc-managed-cert.md`](scripts/xc-managed-cert.md).

Certificate/key material in `clear`/`blindfold` modes comes from **either** inline
sensitive variables **or** local files via `file()` — inline takes precedence when both
are set. When `certificate_chain_pem` is supplied, the intermediate chain is appended
to the leaf certificate (required by most public CAs, e.g. Sectigo).

## Usage

```hcl
module "app_delivery" {
  source = "github.com/<org>/epsilon-demo-automation" # or a local path

  app_namespace = "my-app-ns"
  domains       = ["www.example.com"]

  origin_servers = [
    { type = "dns", value = "origin.example.com" },
    { type = "ip", value = "203.0.113.10" },
  ]

  certificate_mode = "blindfold"
  certificate_pem        = var.certificate_pem
  blindfold_key_location = var.blindfold_key_location
}
```

Provider credentials live in **your** root config, not the module:

```hcl
provider "volterra" {
  api_p12_file = "/path/to/api_credential.p12"
  url          = "https://my-tenant.console.ves.volterra.io/api"
  # password via VES_P12_PASSWORD env var
}
```

## Inputs

| Variable | Default | Purpose |
|---|---|---|
| `app_namespace` | — (required) | Namespace for health check / pool / LB |
| `name_prefix` | `"epsilon"` | Prefix for created resource names |
| `domains` | — (required) | LB domains (non-empty) |
| `origin_servers` | — (required) | `[{ type = "dns"\|"ip", value = "..." }]` |
| `origin_port` | `80` | Origin port |
| `origin_use_tls` | `false` | TLS to origin |
| `origin_tls_skip_verification` | `false` | Skip origin cert verification (insecure; default verifies against the Volterra trusted CA) |
| `health_check_path` | `"/"` | HTTP health check path |
| `health_check_status_codes` | `["200"]` | Expected status codes |
| `healthy_threshold` / `unhealthy_threshold` | `2` / `3` | Health thresholds |
| `health_interval` / `health_timeout` | `10` / `3` | Health timing (seconds) |
| `waf_enforcement` | `"blocking"` | `blocking` or `monitoring` |
| `service_policy_action` | `"allow_all"` | `allow_all` or `deny_all` |
| `advertise_mode` | `"public_default_vip"` | `public_default_vip`, `public_ip`, or `do_not_advertise` |
| `enable_http_redirect` | `true` | HTTP→HTTPS redirect |
| `enable_hsts` | `true` | HSTS header |
| `certificate_mode` | `"clear"` | `clear`, `blindfold`, `vault`, `existing` |
| `certificate_name` | `"<name_prefix>-cert"` | Created cert name |
| `certificate_namespace` | `"shared"` | Created cert namespace |
| `certificate_pem` / `private_key_pem` / `certificate_chain_pem` | `""` (sensitive) | Inline PEM |
| `certificate_file` / `private_key_file` | `""` | PEM file paths |
| `blindfold_key_location` | `""` | Blindfolded key reference |
| `vault_key_location` / `vault_provider` / `vault_key` | `""` | Vault coordinates |
| `existing_certificate_name` / `existing_certificate_namespace` | `""` / `"shared"` | Reference for `existing` mode |

## Outputs

`load_balancer_name`, `load_balancer_domains`, `certificate_id` (null in `existing`
mode), `certificate_reference` (`{name, namespace}`), `origin_pool_name`,
`app_firewall_name`, `service_policy_name`.

## Testing

No tenant credentials are needed for the logic tests — they use `mock_provider`:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test          # 13 plan-level test cases across all certificate modes
```

## Notes

- **Namespaces are not created** by this module; `var.app_namespace` must pre-exist.
- `advertise_mode = "public_ip"` references a Public IP object named
  `<name_prefix>-public-ip` in `shared` that must pre-exist.
- The App Firewall emits a provider **deprecation warning** on `default_bot_setting`.
  The bot-protection setting is a required choice whose only options are both
  provider-deprecated in v0.13.x, so the warning is unavoidable and benign; `validate`
  and `test` still succeed.
- `vault` certificate mode uses the provider's deprecated `vault_secret_info`. Prefer
  `blindfold` or `clear` for new work.
