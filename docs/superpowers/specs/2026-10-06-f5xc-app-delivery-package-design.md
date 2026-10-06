# F5 Distributed Cloud App-Delivery Terraform Package — Design

- **Date:** 2026-10-06
- **Status:** Approved (design); pending implementation plan
- **Provider:** [`volterraedge/volterra`](https://registry.terraform.io/providers/volterraedge/volterra/latest/docs)

## Purpose

A lean, reusable Terraform package that deploys a complete HTTPS application-delivery
stack in F5 Distributed Cloud (XC) with a single `terraform apply`. The defining
requirement is **certificate flexibility**: a customer chooses how their TLS
certificate is supplied — without editing module code — covering every method the
provider and Terraform support.

Success criterion: a customer sets a handful of variables, runs `terraform apply`,
and gets a working HTTPS load balancer fronting a health-checked origin pool, with a
Web Application Firewall and Service Policy applied — having picked their certificate
method via variables alone.

## Scope

In scope (six XC resources + certificate flexibility):

| Resource | Provider resource | Namespace |
|---|---|---|
| App Firewall (WAF) | `volterra_app_firewall` | `shared` |
| Service Policy | `volterra_service_policy` | `shared` |
| Certificate | `volterra_certificate` | `shared` (default; configurable) |
| HTTP Health Check | `volterra_healthcheck` | `var.app_namespace` |
| Origin Pool | `volterra_origin_pool` | `var.app_namespace` |
| HTTPS Load Balancer | `volterra_http_loadbalancer` | `var.app_namespace` |

Out of scope for v1:

- Creating namespaces (the package assumes `shared` and `var.app_namespace` exist).
- Provider credential management (handled in each example's own `provider` block).
- A native Venafi/Sectigo certificate-issuance resource — the provider has none (see
  "Certificate design" → mode `existing`).

## Key research finding (drives the whole design)

Regardless of how a certificate is provisioned, a **custom-certificate** load balancer
always *references a `volterra_certificate` object* the same way:

```hcl
https {
  tls_cert_params {
    certificates { name = "...", namespace = "..." }   # a reference list (name/namespace/tenant)
  }
}
```

Therefore the customer's five requested certificate methods collapse into **two
behaviors** at the Terraform layer:

1. **Create a `volterra_certificate`** — differing only by the `private_key` secret
   sub-block: `clear` / `blindfold` / `vault`.
2. **Reference an existing `volterra_certificate`** — the LB points at a cert already
   in the tenant. This single behavior covers both "reference an existing cert" *and*
   **"Sectigo CA → Venafi → XC managed certificate"**: XC's own Certificate Management
   / CA integration (a console/API feature **not** exposed by the Terraform provider)
   produces exactly such a cert object, which the LB then references. So the Venafi/XC
   path requires no extra Terraform resource — only documentation and an optional API
   helper script.

## Package structure

Single reusable root module (chosen over a cert submodule for leanness — the
certificate is essentially one resource), with `examples/` per certificate path.

```
epsilon-demo-automation/
  main.tf              # app_firewall + service_policy (shared); healthcheck, origin_pool, http_loadbalancer (app ns)
  certificate.tf       # ONE volterra_certificate, count-gated, dynamic private_key secret block
  variables.tf         # all inputs + validation
  locals.tf            # cert source resolution, cert reference selection, origin mapping
  outputs.tf           # lb host/CNAME, cert id, resource ids
  versions.tf          # required_version + volterraedge/volterra in required_providers (NO provider config)
  terraform.tfvars.example
  README.md
  CLAUDE.md            # repo guidance (satisfies the /init intent)
  examples/
    clear-inline/      # certificate_mode=clear, PEM via sensitive vars
    clear-file/        # certificate_mode=clear, PEM via file()
    blindfold/         # certificate_mode=blindfold, pre-encrypted key
    vault/             # certificate_mode=vault  (flagged: provider-deprecated)
    existing-ref/      # certificate_mode=existing  (also the Venafi / XC-managed story)
  scripts/
    xc-managed-cert.md # documented XC Certificate Management API flow (+ optional helper)
  tests/
    certificate_modes.tftest.hcl   # mock_provider, plan-level assertions
```

The module declares `required_providers` only; each example supplies the `volterra`
`provider` block (`api_p12_file`/`api_cert`+`api_key` or env vars). This keeps the
module portable and credential-free.

## Certificate design (the core)

### Input: mode

`certificate_mode` ∈ `{clear, blindfold, vault, existing}` (validated).

### Input: source of PEM material (for clear mode; cert body for blindfold)

Two interchangeable sources, resolved in `locals.tf`:

- **Inline sensitive variables** — `certificate_pem`, `private_key_pem` (and
  `certificate_chain_pem`), marked `sensitive = true`.
- **Local files** — `certificate_file`, `private_key_file` paths read via `file()`.

```hcl
# locals.tf
cert_pem = var.certificate_pem != "" ? var.certificate_pem : (
           var.certificate_file != "" ? file(var.certificate_file) : "")
key_pem  = var.private_key_pem  != "" ? var.private_key_pem  : (
           var.private_key_file  != "" ? file(var.private_key_file)  : "")

cert_ref_name      = var.certificate_mode == "existing" ? var.existing_certificate_name      : var.certificate_name
cert_ref_namespace = var.certificate_mode == "existing" ? var.existing_certificate_namespace : var.certificate_namespace
```

### The switch (`certificate.tf`)

```hcl
resource "volterra_certificate" "this" {
  count           = var.certificate_mode == "existing" ? 0 : 1
  name            = var.certificate_name
  namespace       = var.certificate_namespace            # default "shared"
  certificate_url = "string:///${base64encode(local.cert_pem)}"

  private_key {
    dynamic "clear_secret_info" {
      for_each = var.certificate_mode == "clear" ? [1] : []
      content { url = "string:///${base64encode(local.key_pem)}" }
    }
    dynamic "blindfold_secret_info" {
      for_each = var.certificate_mode == "blindfold" ? [1] : []
      content {
        location = var.blindfold_key_location            # e.g. "string:///<blindfolded>"
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
    precondition {                                         # fail at plan, not in provider
      condition = (
        var.certificate_mode == "clear"     ? (local.cert_pem != "" && local.key_pem != "") :
        var.certificate_mode == "blindfold" ? (local.cert_pem != "" && var.blindfold_key_location != "") :
        var.certificate_mode == "vault"     ? (var.vault_key_location != "" && var.vault_provider != "") : true
      )
      error_message = "Inputs required for certificate_mode=${var.certificate_mode} are missing."
    }
  }
}
```

### Provider conventions confirmed from docs

- Secret material uses the `string:///<base64-PEM>` URL convention for both
  `certificate_url` and `clear_secret_info.url`.
- `certificate_url` is **Required**; `private_key` is **Required** with exactly one of
  `blindfold_secret_info | clear_secret_info | vault_secret_info | wingman_secret_info`.
- **`vault_secret_info` and `wingman_secret_info` are marked _Deprecated_ in the
  provider.** The package supports `vault` (requested) but README/example carry the
  deprecation caveat; `wingman` is omitted from v1. `clear` and `blindfold` are the
  current, recommended paths.

## Resource composition

### Shared namespace

- **`volterra_app_firewall`** — satisfies its seven required oneofs with safe
  defaults: `allow_all_response_codes`, `disable_anonymization`,
  `use_default_blocking_page`, `default_bot_setting`, `default_detection_settings`,
  enforcement = `var.waf_enforcement` (`blocking` default | `monitoring`),
  `disable_ai_enhancements`.
- **`volterra_service_policy`** — `algo = "FIRST_MATCH"`; default
  `allow_all_requests = true` + `any_server = true` (both required oneofs). A
  `service_policy_action` variable allows `deny_all_requests` instead.

### App namespace (`var.app_namespace`)

- **`volterra_healthcheck`** — `http_health_check { use_origin_server_name = true,
  path = var.health_check_path (default "/") }`, `expected_status_codes` default
  `["200"]`; `healthy_threshold`/`interval`/`timeout`/`unhealthy_threshold` as
  variables with sane defaults (e.g. 2 / 10 / 3 / 3). (Thresholds/interval/timeout are
  Required by the provider.)
- **`volterra_origin_pool`** — `endpoint_selection = ["LOCAL_PREFERRED"]`,
  `loadbalancer_algorithm = ["ROUND_ROBIN"]`, `port = var.origin_port` (default 80),
  `no_tls = true` by default (toggle `origin_use_tls` for `use_tls{...}`),
  `healthcheck { name, namespace }` referencing the health check. `origin_servers`
  built from `var.origin_servers = [{ type = "dns"|"ip", value = "..." }]` via a
  dynamic block emitting `public_name { dns_name = value }` or `public_ip { ip = value }`.
- **`volterra_http_loadbalancer`** — `domains = var.domains`;
  `https { tls_cert_params { certificates { name = local.cert_ref_name,
  namespace = local.cert_ref_namespace }, no_mtls = true }, port = 443,
  http_redirect = true, add_hsts = true }` (redirect + HSTS default on, both
  toggleable); `app_firewall { name, namespace = "shared" }`;
  `active_service_policies { policies { name, namespace = "shared" } }`;
  `default_route_pools { pool { name, namespace = var.app_namespace } }`;
  advertisement via `var.advertise_mode` (`public_default_vip` default →
  `advertise_on_public_default_vip = true`; `public_ip` → `advertise_on_public {
  public_ip { ... } }`; `do_not_advertise`). All remaining ~16 mandatory oneofs set to
  safe defaults: `no_challenge`, `round_robin`, `disable_api_definition`,
  `disable_api_discovery`, `disable_api_testing`,
  `disable_malicious_user_detection`, `disable_malware_protection`,
  `disable_rate_limit`, `default_sensitive_data_policy`, `disable_threat_mesh`,
  `disable_trust_client_ip_headers`, `user_id_client_ip`.

### Namespaces

The module does **not** create namespaces. `shared` is built in; `var.app_namespace`
must pre-exist. (A future enhancement could optionally create it via
`volterra_namespace`.)

## Variables (summary)

| Variable | Default | Purpose |
|---|---|---|
| `app_namespace` | — (required) | Namespace for healthcheck/pool/LB |
| `name_prefix` | `"epsilon"` | Prefix for resource names |
| `domains` | — (required, non-empty) | LB domains |
| `certificate_mode` | `"clear"` | `clear`\|`blindfold`\|`vault`\|`existing` |
| `certificate_name` | `"${name_prefix}-cert"` | Name of created cert |
| `certificate_namespace` | `"shared"` | Namespace of created cert |
| `certificate_pem` / `private_key_pem` / `certificate_chain_pem` | `""` (sensitive) | Inline PEM |
| `certificate_file` / `private_key_file` | `""` | PEM file paths |
| `blindfold_key_location` | `""` | Blindfolded key location |
| `vault_key_location` / `vault_provider` / `vault_key` | `""` | Vault secret coordinates |
| `existing_certificate_name` / `existing_certificate_namespace` | `""` / `"shared"` | Reference for `existing` mode |
| `origin_servers` | — (required) | `[{ type, value }]` list |
| `origin_port` | `80` | Origin port |
| `origin_use_tls` | `false` | TLS to origin |
| `health_check_path` | `"/"` | HTTP health check path |
| `waf_enforcement` | `"blocking"` | `blocking`\|`monitoring` |
| `service_policy_action` | `"allow_all"` | `allow_all`\|`deny_all` |
| `advertise_mode` | `"public_default_vip"` | advertisement choice |
| `enable_http_redirect` | `true` | HTTP→HTTPS redirect |
| `enable_hsts` | `true` | HSTS |

## Error handling

- `variable validation` blocks: `certificate_mode`, origin entry `type` (`dns`/`ip`),
  `waf_enforcement`, `service_policy_action`, `advertise_mode`, non-empty `domains`.
- `lifecycle { precondition }` on `volterra_certificate.this` (above): each mode
  asserts its own inputs are present, failing at plan time with a clear message.

## Testing

1. **Format & validate (no creds):** `terraform fmt -check -recursive` and
   `terraform validate` on the module and every example.
2. **Logic (no creds):** `tests/certificate_modes.tftest.hcl` using
   `mock_provider "volterra"` with `command = plan`:
   - `clear` / `blindfold` / `vault` ⇒ `volterra_certificate.this` has `count = 1`
     and the correct secret sub-block present.
   - `existing` ⇒ `count = 0`, and the LB references `existing_certificate_name`.
   - Origin list with mixed `dns`/`ip` ⇒ correct `public_name`/`public_ip` blocks.
   - Requires Terraform ≥ 1.7 (native test framework + `mock_provider`).
3. **Live (creds; documented, manual):** `terraform plan`/`apply` per example against a
   real tenant.

## Defaults & assumptions (all overridable)

- Certificate created in `shared` (reusable across app LBs).
- Plaintext origin (`no_tls`), origin port 80 (health check is "basic HTTP").
- Advertisement via `advertise_on_public_default_vip` (no Public IP object required).
- WAF enforcement = blocking; service policy = allow-all; HTTP→HTTPS redirect + HSTS on.
- Target Terraform `>= 1.7`; `volterraedge/volterra` provider pinned with `~>` in
  `versions.tf`.

## Open items to confirm during implementation

- Exact provider version to pin in `versions.tf` (latest at build time).
- Exact `volterra` provider authentication arguments for example `provider` blocks
  (`api_p12_file` + `VES_P12_PASSWORD`, vs `api_cert`/`api_key`).
- Confirm `http_redirect` / `add_hsts` argument names/placement inside the `https`
  block against the installed provider version during `terraform validate`.
