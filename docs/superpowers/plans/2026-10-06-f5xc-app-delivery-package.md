# F5 Distributed Cloud App-Delivery Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a lean, reusable Terraform module that deploys an HTTPS application-delivery stack in F5 Distributed Cloud (WAF + Service Policy in `shared`; health check, origin pool, HTTPS load balancer in an app namespace) with customer-selectable TLS certificate handling.

**Architecture:** A single root module. All six resources are defined at the root; a single `volterra_certificate` is `count`-gated and uses `dynamic` blocks so one `certificate_mode` variable (`clear`/`blindfold`/`vault`/`existing`) selects the private-key secret type. `locals.tf` resolves PEM material from inline sensitive vars *or* local files, and resolves which certificate the load balancer references (created vs. existing). Each certificate path has an `examples/` root; logic is verified with Terraform's native `.tftest.hcl` framework using `mock_provider` (no tenant credentials needed).

**Tech Stack:** Terraform `>= 1.7`, `volterraedge/volterra` provider `~> 0.13` (latest 0.13.2). Native Terraform test framework (`terraform test`) with `mock_provider`.

**Spec:** `docs/superpowers/specs/2026-10-06-f5xc-app-delivery-package-design.md`

## Global Constraints

- Terraform required version: `>= 1.7` (native test framework + `mock_provider` require 1.7+). Copy verbatim into `versions.tf`.
- Provider: `source = "volterraedge/volterra"`, `version = "~> 0.13"`. Pin in `versions.tf` `required_providers` only — the **module declares no `provider` block**; each example declares its own.
- Provider auth (examples only): `api_p12_file` + `url` (P12 password via `VES_P12_PASSWORD` env var), **or** `api_cert` + `api_key` + `url`. `url` is required and of the form `https://<tenant>.console.ves.volterra.io/api`.
- Secret material convention: both `certificate_url` and `clear_secret_info.url` take `string:///<base64-of-PEM>` — always wrap PEM as `"string:///${base64encode(pem)}"`.
- Namespaces are **not** created by this module. `shared` is built in; `var.app_namespace` must pre-exist in the tenant.
- WAF (`volterra_app_firewall`) must set seven required oneofs; HTTPS `volterra_http_loadbalancer` must set ~16 required oneofs; `volterra_service_policy` must set two (rule-choice + server-choice). Exact minimal picks are given in each task.
- `vault_secret_info` and `wingman_secret_info` are **provider-deprecated**. Support `vault` (per requirement) with a documented caveat; do **not** implement `wingman` in v1.
- Resource naming: `"${var.name_prefix}-<role>"` (e.g. `epsilon-waf`, `epsilon-cert`, `epsilon-pool`, `epsilon-hc`, `epsilon-lb`). `name_prefix` default `"epsilon"`.

## Review Focus

- **`certificate_mode = "existing"` with the creation vars still set** — the LB must reference `existing_certificate_name`/`existing_certificate_namespace` and create **zero** certificates; stray `certificate_pem` must be ignored, not create a second cert. (Test in Task 9.)
- **Inline PEM *and* file path both provided for the same material** — `locals` precedence must be deterministic (inline wins); it must never concatenate or error ambiguously. (Test in Task 9.)
- **`origin_servers` with mixed `dns` and `ip` entries** — each entry must map to the correct `public_name`/`public_ip` block; an unknown `type` must fail validation at plan, not silently drop the server. (Validation in Task 4; test in Task 9.)
- **`certificate_mode = "clear"` with empty cert/key material** — must fail at `plan` via precondition with a readable message, not surface an opaque provider error at `apply`. (Test in Task 9.)
- **`waf_enforcement`/`service_policy_action`/`advertise_mode` given an out-of-range string** — must be rejected by `variable validation` at plan with the allowed set named, not produce an invalid API body. (Validation + test in Tasks 3/9.)

---

## File Structure

| File | Responsibility |
|---|---|
| `versions.tf` | `required_version`, `required_providers` (volterra `~> 0.13`). No provider config. |
| `variables.tf` | All input variables + `validation` blocks. |
| `locals.tf` | PEM source resolution, cert-reference selection, resource names. |
| `certificate.tf` | Single `count`-gated `volterra_certificate` with dynamic secret blocks + precondition. |
| `main.tf` | `app_firewall`, `service_policy` (shared); `healthcheck`, `origin_pool`, `http_loadbalancer` (app ns). |
| `outputs.tf` | LB host/CNAME, cert id, resource ids. |
| `terraform.tfvars.example` | Commented sample inputs. |
| `README.md` | Usage, cert-mode matrix, auth, testing. |
| `CLAUDE.md` | Repo guidance (satisfies `/init`). |
| `examples/clear-inline/` `clear-file/` `blindfold/` `vault/` `existing-ref/` | One root per cert path: `main.tf` (provider + module call), `variables.tf`/`terraform.tfvars.example`, `README.md`. |
| `scripts/xc-managed-cert.md` | XC Certificate Management (Venafi/Sectigo) API flow — the `existing` story. |
| `tests/certificate_modes.tftest.hcl` | `mock_provider` plan-level assertions for the cert switch, origins, validations. |
| `.gitignore` | Terraform state, `.terraform/`, `*.tfvars` (except `*.example`), P12/PEM/key files. |

Tasks are ordered so the module `terraform validate`s as early as possible, then each later task adds a verifiable slice.

---

### Task 1: Project skeleton — versions, gitignore, validate baseline

**Files:**
- Create: `versions.tf`, `.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: a module directory that `terraform init -backend=false` and `terraform validate` accept (empty config is valid once providers resolve).

- [ ] **Step 1: Write `versions.tf`**

```hcl
terraform {
  required_version = ">= 1.7"

  required_providers {
    volterra = {
      source  = "volterraedge/volterra"
      version = "~> 0.13"
    }
  }
}
```

- [ ] **Step 2: Write `.gitignore`**

```gitignore
# Terraform
.terraform/
.terraform.lock.hcl
*.tfstate
*.tfstate.*
crash.log
crash.*.log

# Variable files (keep examples)
*.tfvars
*.tfvars.json
!*.tfvars.example

# Secrets / credentials
*.p12
*.pem
*.key
```

- [ ] **Step 3: Verify provider resolves and config validates**

Run: `terraform init -backend=false && terraform validate`
Expected: `Terraform has been successfully initialized!` then `Success! The configuration is valid.` (An empty module with only `versions.tf` is valid.)

- [ ] **Step 4: Verify formatting**

Run: `terraform fmt -check -recursive`
Expected: exit 0, no files listed.

- [ ] **Step 5: Commit**

```bash
git add versions.tf .gitignore
git commit -m "chore: terraform skeleton with volterra provider pin"
```

---

### Task 2: Core variables (non-certificate)

**Files:**
- Create: `variables.tf` (core section)
- Test: none yet (validations tested in Task 9).

**Interfaces:**
- Produces: variables `app_namespace` (string, required), `name_prefix` (string, default `"epsilon"`), `domains` (list(string), required), `origin_servers` (list(object({type=string, value=string})), required), `origin_port` (number, default 80), `origin_use_tls` (bool, default false), `health_check_path` (string, default "/"), `health_check_status_codes` (list(string), default `["200"]`), `healthy_threshold`/`unhealthy_threshold`/`health_interval`/`health_timeout` (numbers, defaults 2/3/10/3), `waf_enforcement` (string, default "blocking"), `service_policy_action` (string, default "allow_all"), `advertise_mode` (string, default "public_default_vip"), `enable_http_redirect` (bool, default true), `enable_hsts` (bool, default true).

- [ ] **Step 1: Write the core variables with validation**

```hcl
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
  description = "If true, connect to origins over TLS (skips server verification by default)."
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
```

- [ ] **Step 2: Validate**

Run: `terraform fmt -check -recursive && terraform validate`
Expected: formatted; `Success! The configuration is valid.` (Unused variables are valid in Terraform.)

- [ ] **Step 3: Commit**

```bash
git add variables.tf
git commit -m "feat: core input variables with validation"
```

---

### Task 3: Certificate variables

**Files:**
- Modify: `variables.tf` (append certificate section)

**Interfaces:**
- Produces: `certificate_mode` (string, default "clear", validated to clear/blindfold/vault/existing), `certificate_name` (string, default ""), `certificate_namespace` (string, default "shared"), `certificate_pem`/`private_key_pem`/`certificate_chain_pem` (string, default "", sensitive), `certificate_file`/`private_key_file` (string, default ""), `blindfold_key_location` (string, default ""), `vault_key_location`/`vault_provider`/`vault_key` (string, default ""), `existing_certificate_name` (string, default ""), `existing_certificate_namespace` (string, default "shared").

- [ ] **Step 1: Append certificate variables**

```hcl
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
```

- [ ] **Step 2: Validate**

Run: `terraform fmt -check -recursive && terraform validate`
Expected: formatted; valid.

- [ ] **Step 3: Commit**

```bash
git add variables.tf
git commit -m "feat: certificate input variables with mode validation"
```

---

### Task 4: Locals — name, PEM source, cert reference, origin mapping

**Files:**
- Create: `locals.tf`

**Interfaces:**
- Consumes: all variables from Tasks 2–3.
- Produces locals: `cert_name` (string), `cert_pem` (string), `key_pem` (string), `create_certificate` (bool), `cert_ref_name` (string), `cert_ref_namespace` (string), `names` (object of per-resource names).

- [ ] **Step 1: Write `locals.tf`**

```hcl
locals {
  cert_name = var.certificate_name != "" ? var.certificate_name : "${var.name_prefix}-cert"

  names = {
    waf = "${var.name_prefix}-waf"
    svc = "${var.name_prefix}-svc-policy"
    hc  = "${var.name_prefix}-hc"
    pool = "${var.name_prefix}-pool"
    lb  = "${var.name_prefix}-lb"
  }

  # Inline PEM takes precedence over file paths; empty string means "not provided".
  cert_pem = var.certificate_pem != "" ? var.certificate_pem : (
    var.certificate_file != "" ? file(var.certificate_file) : ""
  )
  key_pem = var.private_key_pem != "" ? var.private_key_pem : (
    var.private_key_file != "" ? file(var.private_key_file) : ""
  )
  chain_pem = var.certificate_chain_pem

  create_certificate = var.certificate_mode != "existing"

  cert_ref_name = var.certificate_mode == "existing" ? var.existing_certificate_name : local.cert_name
  cert_ref_namespace = var.certificate_mode == "existing" ? var.existing_certificate_namespace : var.certificate_namespace
}
```

- [ ] **Step 2: Validate**

Run: `terraform fmt -check -recursive && terraform validate`
Expected: formatted; valid. (`file()` is not evaluated until a value needs it, so empty defaults don't error here.)

- [ ] **Step 3: Commit**

```bash
git add locals.tf
git commit -m "feat: locals for naming, PEM resolution, and cert reference"
```

---

### Task 5: Certificate resource (the switch)

**Files:**
- Create: `certificate.tf`

**Interfaces:**
- Consumes: variables (Task 3), locals (Task 4).
- Produces: resource `volterra_certificate.this` (indexed by `count`, so referenced as `volterra_certificate.this[0]`). Later tasks reference the cert **by name** through `local.cert_ref_name`/`local.cert_ref_namespace`, not by resource attribute, so the LB works in both created and existing modes.

- [ ] **Step 1: Write `certificate.tf`**

```hcl
resource "volterra_certificate" "this" {
  count     = local.create_certificate ? 1 : 0
  name      = local.cert_name
  namespace = var.certificate_namespace

  certificate_url = "string:///${base64encode(local.cert_pem)}"

  private_key {
    dynamic "clear_secret_info" {
      for_each = var.certificate_mode == "clear" ? [1] : []
      content {
        url = "string:///${base64encode(local.key_pem)}"
      }
    }

    dynamic "blindfold_secret_info" {
      for_each = var.certificate_mode == "blindfold" ? [1] : []
      content {
        location = var.blindfold_key_location
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
    precondition {
      condition = (
        var.certificate_mode == "clear" ? (local.cert_pem != "" && local.key_pem != "") : (
          var.certificate_mode == "blindfold" ? (local.cert_pem != "" && var.blindfold_key_location != "") : (
            var.certificate_mode == "vault" ? (var.vault_key_location != "" && var.vault_provider != "") : true
          )
        )
      )
      error_message = "Missing inputs for certificate_mode=${var.certificate_mode}: clear needs cert+key material; blindfold needs cert + blindfold_key_location; vault needs vault_key_location + vault_provider."
    }
    precondition {
      condition     = var.certificate_mode != "existing" || var.existing_certificate_name != ""
      error_message = "certificate_mode=existing requires existing_certificate_name."
    }
  }
}
```

Note: the second precondition lives here even though `count=0` in existing mode — a `count`-gated resource still evaluates preconditions when its count expression and referenced values are known. If the installed provider rejects an empty `certificate_chain` behavior differently, the chain is handled as an optional attribute in README; v1 does not set `certificate_chain` unless provided (kept out to stay minimal — add in a follow-up if needed).

- [ ] **Step 2: Validate with a clear-mode fixture**

Run:
```bash
terraform validate
```
Expected: valid. (Full plan behavior is exercised by the test suite in Task 9; `validate` confirms the HCL and dynamic blocks are well-formed.)

- [ ] **Step 3: Commit**

```bash
git add certificate.tf
git commit -m "feat: count-gated certificate with dynamic secret-type blocks"
```

---

### Task 6: Shared-namespace resources — app firewall & service policy

**Files:**
- Create: `main.tf` (shared section)

**Interfaces:**
- Produces: `volterra_app_firewall.this` (name `local.names.waf`, namespace `shared`), `volterra_service_policy.this` (name `local.names.svc`, namespace `shared`). Referenced later by name/namespace in the LB.

- [ ] **Step 1: Write the shared resources**

```hcl
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
```

- [ ] **Step 2: Validate**

Run: `terraform fmt -check -recursive && terraform validate`
Expected: formatted; valid.

- [ ] **Step 3: Commit**

```bash
git add main.tf
git commit -m "feat: shared-namespace app firewall and service policy"
```

---

### Task 7: App-namespace resources — health check & origin pool

**Files:**
- Modify: `main.tf` (append app-namespace section)

**Interfaces:**
- Consumes: `local.names`, origin/health variables, `volterra_healthcheck.this` referenced by the pool.
- Produces: `volterra_healthcheck.this`, `volterra_origin_pool.this` (name `local.names.pool`, namespace `var.app_namespace`). Pool referenced by LB.

- [ ] **Step 1: Append health check and origin pool**

```hcl
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
```

Note on types: the Explore findings show `endpoint_selection`/`loadbalancer_algorithm` as single strings in the schema table but the doc example wraps them in list brackets (`["LOCAL_PREFERRED"]`). During Step 2, if `terraform validate` reports a type error, switch these two to the list form `["LOCAL_PREFERRED"]` / `["ROUND_ROBIN"]`. Resolve to whatever the installed provider 0.13.x accepts; record the resolved form in a code comment.

- [ ] **Step 2: Validate**

Run: `terraform fmt -check -recursive && terraform validate`
Expected: formatted; valid. If a type error appears on `endpoint_selection`/`loadbalancer_algorithm`, apply the list-form fix noted above, re-run, confirm valid.

- [ ] **Step 3: Commit**

```bash
git add main.tf
git commit -m "feat: health check and origin pool with dns/ip origin mapping"
```

---

### Task 8: HTTPS load balancer

**Files:**
- Modify: `main.tf` (append LB)

**Interfaces:**
- Consumes: `local.cert_ref_name`/`local.cert_ref_namespace`, `local.names`, the firewall/policy/pool resources, advertise/redirect/hsts variables.
- Produces: `volterra_http_loadbalancer.this`.

- [ ] **Step 1: Append the load balancer**

```hcl
resource "volterra_http_loadbalancer" "this" {
  name      = local.names.lb
  namespace = var.app_namespace
  domains   = var.domains

  https {
    port          = 443
    http_redirect = var.enable_http_redirect
    add_hsts      = var.enable_hsts

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
    namespace = "shared"
  }

  active_service_policies {
    policies {
      name      = volterra_service_policy.this.name
      namespace = "shared"
    }
  }

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
```

Note: `advertise_mode = "public_ip"` references a Public IP object named `<name_prefix>-public-ip` in `shared` that must pre-exist; README documents this. The default `public_default_vip` needs no object. If `terraform validate` on the installed provider flags `http_redirect`/`add_hsts` as not allowed directly inside `https` (placement differs by provider version), move them per the provider's `https` schema and record the resolved placement in a comment; keep both wired to their variables.

- [ ] **Step 2: Validate**

Run: `terraform fmt -check -recursive && terraform validate`
Expected: formatted; valid.

- [ ] **Step 3: Commit**

```bash
git add main.tf
git commit -m "feat: HTTPS load balancer referencing cert, WAF, policy, pool"
```

---

### Task 9: Test suite — cert switch, origins, validations (mock_provider)

**Files:**
- Create: `tests/certificate_modes.tftest.hcl`
- Create: `tests/fixtures/cert.pem`, `tests/fixtures/key.pem` (dummy non-secret PEM-shaped text for file() path tests)

**Interfaces:**
- Consumes: the whole module via `mock_provider`.
- Produces: `terraform test` pass covering the Review Focus items.

- [ ] **Step 1: Create dummy fixtures**

`tests/fixtures/cert.pem`:
```
-----BEGIN CERTIFICATE-----
TEST-NOT-A-REAL-CERT
-----END CERTIFICATE-----
```
`tests/fixtures/key.pem`:
```
-----BEGIN PRIVATE KEY-----
TEST-NOT-A-REAL-KEY
-----END PRIVATE KEY-----
```
(These are inert placeholders so `file()` resolves during plan; `mock_provider` never contacts a tenant.)

- [ ] **Step 2: Write the test file**

```hcl
mock_provider "volterra" {}

variables {
  app_namespace  = "app-ns"
  domains        = ["www.example.com"]
  origin_servers = [{ type = "dns", value = "origin.example.com" }]
}

# clear mode (inline) creates exactly one certificate
run "clear_mode_creates_cert" {
  command = plan
  variables {
    certificate_mode = "clear"
    certificate_pem  = "-----BEGIN CERTIFICATE-----\nX\n-----END CERTIFICATE-----"
    private_key_pem  = "-----BEGIN PRIVATE KEY-----\nY\n-----END PRIVATE KEY-----"
  }
  assert {
    condition     = length(volterra_certificate.this) == 1
    error_message = "clear mode must create exactly one certificate"
  }
  assert {
    condition     = volterra_http_loadbalancer.this.https[0].tls_cert_params[0].certificates[0].name == local.cert_name
    error_message = "LB must reference the created certificate by name"
  }
}

# file source resolves when inline is empty
run "clear_mode_from_files" {
  command = plan
  variables {
    certificate_mode = "clear"
    certificate_file = "tests/fixtures/cert.pem"
    private_key_file = "tests/fixtures/key.pem"
  }
  assert {
    condition     = length(volterra_certificate.this) == 1
    error_message = "clear mode via files must create one certificate"
  }
}

# inline precedence over file
run "inline_beats_file" {
  command = plan
  variables {
    certificate_mode = "clear"
    certificate_pem  = "-----BEGIN CERTIFICATE-----\nINLINE\n-----END CERTIFICATE-----"
    private_key_pem  = "-----BEGIN PRIVATE KEY-----\nINLINE\n-----END PRIVATE KEY-----"
    certificate_file = "tests/fixtures/cert.pem"
    private_key_file = "tests/fixtures/key.pem"
  }
  assert {
    condition     = local.cert_pem == "-----BEGIN CERTIFICATE-----\nINLINE\n-----END CERTIFICATE-----"
    error_message = "inline PEM must take precedence over file"
  }
}

# existing mode creates zero certificates and references the existing one
run "existing_mode_no_cert" {
  command = plan
  variables {
    certificate_mode          = "existing"
    certificate_pem           = "-----BEGIN CERTIFICATE-----\nSTRAY\n-----END CERTIFICATE-----"
    existing_certificate_name = "preprovisioned-cert"
  }
  assert {
    condition     = length(volterra_certificate.this) == 0
    error_message = "existing mode must create zero certificates even if cert PEM is set"
  }
  assert {
    condition     = volterra_http_loadbalancer.this.https[0].tls_cert_params[0].certificates[0].name == "preprovisioned-cert"
    error_message = "existing mode must reference existing_certificate_name"
  }
}

# blindfold mode
run "blindfold_mode" {
  command = plan
  variables {
    certificate_mode       = "blindfold"
    certificate_pem        = "-----BEGIN CERTIFICATE-----\nX\n-----END CERTIFICATE-----"
    blindfold_key_location = "string:///blindfolded"
  }
  assert {
    condition     = length(volterra_certificate.this) == 1
    error_message = "blindfold mode must create one certificate"
  }
}

# mixed dns/ip origins both map
run "mixed_origins" {
  command = plan
  variables {
    certificate_mode = "existing"
    existing_certificate_name = "c"
    origin_servers = [
      { type = "dns", value = "a.example.com" },
      { type = "ip", value = "203.0.113.10" },
    ]
  }
  assert {
    condition     = length(volterra_origin_pool.this.origin_servers) == 2
    error_message = "both origin servers must be present"
  }
}

# clear mode missing material fails precondition
run "clear_missing_material_fails" {
  command         = plan
  expect_failures = [volterra_certificate.this]
  variables {
    certificate_mode = "clear"
  }
}

# invalid enum rejected by variable validation
run "invalid_waf_mode_rejected" {
  command         = plan
  expect_failures = [var.waf_enforcement]
  variables {
    certificate_mode          = "existing"
    existing_certificate_name = "c"
    waf_enforcement           = "bogus"
  }
}

# invalid origin type rejected
run "invalid_origin_type_rejected" {
  command         = plan
  expect_failures = [var.origin_servers]
  variables {
    certificate_mode          = "existing"
    existing_certificate_name = "c"
    origin_servers            = [{ type = "ftp", value = "x" }]
  }
}
```

- [ ] **Step 3: Run the tests**

Run: `terraform test`
Expected: all `run` blocks pass. If an assertion path like `https[0].tls_cert_params[0]...` doesn't match the installed provider's attribute nesting, adjust the index path to the provider's actual shape (confirmed via `terraform plan` output) and re-run. The *intent* of each assertion stays fixed.

- [ ] **Step 4: Commit**

```bash
git add tests/
git commit -m "test: mock_provider plan tests for cert modes, origins, validation"
```

---

### Task 10: Outputs

**Files:**
- Create: `outputs.tf`

**Interfaces:**
- Consumes: the LB, cert, pool resources.
- Produces: outputs `load_balancer_name`, `load_balancer_host` (if exposed by provider as an attribute; otherwise the domains), `certificate_id`, `origin_pool_name`, `app_firewall_name`, `service_policy_name`.

- [ ] **Step 1: Write `outputs.tf`**

```hcl
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
```

- [ ] **Step 2: Validate and re-run tests**

Run: `terraform fmt -check -recursive && terraform validate && terraform test`
Expected: formatted; valid; all tests pass.

- [ ] **Step 3: Commit**

```bash
git add outputs.tf
git commit -m "feat: module outputs"
```

---

### Task 11: Example roots (five)

**Files:**
- Create under each of `examples/clear-inline/`, `examples/clear-file/`, `examples/blindfold/`, `examples/vault/`, `examples/existing-ref/`: `main.tf`, `terraform.tfvars.example`, `README.md`.

**Interfaces:**
- Consumes: the root module via relative `source = "../.."`.
- Produces: runnable example roots, each `terraform validate`-clean.

- [ ] **Step 1: Write `examples/clear-inline/main.tf`**

```hcl
terraform {
  required_version = ">= 1.7"
  required_providers {
    volterra = {
      source  = "volterraedge/volterra"
      version = "~> 0.13"
    }
  }
}

provider "volterra" {
  api_p12_file = var.api_p12_file
  url          = var.api_url
  # P12 password comes from the VES_P12_PASSWORD environment variable.
}

variable "api_p12_file" { type = string }
variable "api_url" { type = string }
variable "certificate_pem" {
  type      = string
  sensitive = true
}
variable "private_key_pem" {
  type      = string
  sensitive = true
}

module "app_delivery" {
  source = "../.."

  app_namespace = "my-app-ns"
  domains       = ["www.example.com"]

  origin_servers = [
    { type = "dns", value = "origin.example.com" },
  ]

  certificate_mode = "clear"
  certificate_pem  = var.certificate_pem
  private_key_pem  = var.private_key_pem
}

output "load_balancer_domains" {
  value = module.app_delivery.load_balancer_domains
}
```

- [ ] **Step 2: Write `examples/clear-inline/terraform.tfvars.example`**

```hcl
api_p12_file = "/path/to/api_credential.p12"
api_url      = "https://my-tenant.console.ves.volterra.io/api"
# Provide PEMs via TF_VAR_certificate_pem / TF_VAR_private_key_pem env vars,
# or uncomment and paste here (keep this file out of version control):
# certificate_pem = "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----"
# private_key_pem = "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
```

- [ ] **Step 3: Write `examples/clear-file/main.tf`** (differs: file inputs)

```hcl
terraform {
  required_version = ">= 1.7"
  required_providers {
    volterra = {
      source  = "volterraedge/volterra"
      version = "~> 0.13"
    }
  }
}

provider "volterra" {
  api_p12_file = var.api_p12_file
  url          = var.api_url
}

variable "api_p12_file" { type = string }
variable "api_url" { type = string }

module "app_delivery" {
  source = "../.."

  app_namespace = "my-app-ns"
  domains       = ["www.example.com"]

  origin_servers = [
    { type = "ip", value = "203.0.113.10" },
  ]

  certificate_mode = "clear"
  certificate_file = "${path.module}/cert.pem"
  private_key_file = "${path.module}/key.pem"
}
```

With `examples/clear-file/terraform.tfvars.example`:
```hcl
api_p12_file = "/path/to/api_credential.p12"
api_url      = "https://my-tenant.console.ves.volterra.io/api"
# Place cert.pem and key.pem in this directory (git-ignored).
```

- [ ] **Step 4: Write `examples/blindfold/main.tf`** (differs: blindfold)

```hcl
terraform {
  required_version = ">= 1.7"
  required_providers {
    volterra = {
      source  = "volterraedge/volterra"
      version = "~> 0.13"
    }
  }
}

provider "volterra" {
  api_p12_file = var.api_p12_file
  url          = var.api_url
}

variable "api_p12_file" { type = string }
variable "api_url" { type = string }
variable "certificate_pem" {
  type      = string
  sensitive = true
}
variable "blindfold_key_location" { type = string }

module "app_delivery" {
  source = "../.."

  app_namespace = "my-app-ns"
  domains       = ["www.example.com"]

  origin_servers = [
    { type = "dns", value = "origin.example.com" },
  ]

  certificate_mode       = "blindfold"
  certificate_pem        = var.certificate_pem
  blindfold_key_location = var.blindfold_key_location
}
```

With `examples/blindfold/terraform.tfvars.example`:
```hcl
api_p12_file           = "/path/to/api_credential.p12"
api_url                = "https://my-tenant.console.ves.volterra.io/api"
# Blindfold the key offline first with vesctl:
#   vesctl request secrets encrypt --policy-document policy.json key.pem
# Then set the resulting location (e.g. "string:///<base64>"):
# blindfold_key_location = "string:///..."
```

- [ ] **Step 5: Write `examples/vault/main.tf`** (differs: vault + deprecation note)

```hcl
terraform {
  required_version = ">= 1.7"
  required_providers {
    volterra = {
      source  = "volterraedge/volterra"
      version = "~> 0.13"
    }
  }
}

provider "volterra" {
  api_p12_file = var.api_p12_file
  url          = var.api_url
}

variable "api_p12_file" { type = string }
variable "api_url" { type = string }
variable "certificate_pem" {
  type      = string
  sensitive = true
}

# NOTE: vault_secret_info is marked DEPRECATED in the volterra provider.
# Prefer clear or blindfold for new deployments.
module "app_delivery" {
  source = "../.."

  app_namespace = "my-app-ns"
  domains       = ["www.example.com"]

  origin_servers = [
    { type = "dns", value = "origin.example.com" },
  ]

  certificate_mode   = "vault"
  certificate_pem    = var.certificate_pem
  vault_key_location = "secret/data/tls/www-example-com"
  vault_provider     = "my-vault-sma"
}
```

With `examples/vault/terraform.tfvars.example`:
```hcl
api_p12_file = "/path/to/api_credential.p12"
api_url      = "https://my-tenant.console.ves.volterra.io/api"
# Requires a Secret Management Access (SMA) object integrating Hashicorp Vault.
```

- [ ] **Step 6: Write `examples/existing-ref/main.tf`** (differs: existing / XC-managed)

```hcl
terraform {
  required_version = ">= 1.7"
  required_providers {
    volterra = {
      source  = "volterraedge/volterra"
      version = "~> 0.13"
    }
  }
}

provider "volterra" {
  api_p12_file = var.api_p12_file
  url          = var.api_url
}

variable "api_p12_file" { type = string }
variable "api_url" { type = string }

# Use this mode when the certificate is managed outside Terraform:
# a pre-uploaded custom cert, OR an XC-managed certificate issued via the
# Sectigo CA -> Venafi -> F5 Distributed Cloud integration (see
# scripts/xc-managed-cert.md). Terraform only references it by name.
module "app_delivery" {
  source = "../.."

  app_namespace = "my-app-ns"
  domains       = ["www.example.com"]

  origin_servers = [
    { type = "dns", value = "origin.example.com" },
  ]

  certificate_mode               = "existing"
  existing_certificate_name      = "www-example-com"
  existing_certificate_namespace = "shared"
}
```

With `examples/existing-ref/terraform.tfvars.example`:
```hcl
api_p12_file = "/path/to/api_credential.p12"
api_url      = "https://my-tenant.console.ves.volterra.io/api"
```

- [ ] **Step 7: Write a short `README.md` in each example**

Each README states: what cert path it shows, required env vars (`VES_P12_PASSWORD`, any `TF_VAR_*`), and the run sequence:
```bash
export VES_P12_PASSWORD=...        # P12 password
terraform init
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```
The `vault/` README additionally states the provider deprecation of `vault_secret_info`. The `existing-ref/` README points to `scripts/xc-managed-cert.md` for the Venafi/XC-managed flow.

- [ ] **Step 8: Validate every example**

Run:
```bash
for d in examples/*/; do (cd "$d" && terraform init -backend=false >/dev/null && terraform validate) || exit 1; done
terraform fmt -check -recursive
```
Expected: each example prints `Success! The configuration is valid.`; fmt clean.

- [ ] **Step 9: Commit**

```bash
git add examples/
git commit -m "docs: five example roots, one per certificate mode"
```

---

### Task 12: XC-managed certificate guide (Venafi/Sectigo)

**Files:**
- Create: `scripts/xc-managed-cert.md`

**Interfaces:**
- Consumes: nothing (documentation). Referenced by `examples/existing-ref/README.md`.
- Produces: the documented API flow that produces a cert object which `certificate_mode = "existing"` then references.

- [ ] **Step 1: Write `scripts/xc-managed-cert.md`**

Content covers:
- Why this is not a Terraform resource: the `volterraedge/volterra` provider exposes no Venafi/Sectigo/ACME issuance resource; XC Certificate Management is a console/API feature.
- The model: XC integrates with a CA (e.g. Sectigo via Venafi); XC issues/auto-renews a **Managed Certificate** object in a namespace; the load balancer references it by name — exactly what `certificate_mode = "existing"` does.
- Steps (console + API outline): configure the CA/Venafi integration in XC; create a managed certificate for the domain; note its name/namespace; set `existing_certificate_name`/`existing_certificate_namespace` in the module.
- An optional `curl` skeleton against the XC public API (`https://<tenant>.console.ves.volterra.io/api/...`) with a placeholder path and a clear note to confirm the exact endpoint against current F5 XC API docs before use (do not fabricate the endpoint).
- A short "verify" step: the certificate appears under Shared Configuration → Certificate Management in the XC console, then the module's `existing` mode references it.

- [ ] **Step 2: Commit**

```bash
git add scripts/xc-managed-cert.md
git commit -m "docs: XC-managed (Venafi/Sectigo) certificate flow for existing mode"
```

---

### Task 13: README and CLAUDE.md

**Files:**
- Create: `README.md`, `CLAUDE.md`, `terraform.tfvars.example`

**Interfaces:**
- Consumes: the whole module.
- Produces: top-level usage docs and agent guidance.

- [ ] **Step 1: Write `README.md`**

Sections:
- **Overview** — what the package deploys (the six resources, namespaces table from the spec).
- **Requirements** — Terraform `>= 1.7`, provider `~> 0.13`, an existing `app_namespace`, API credentials.
- **Certificate modes** — a table: `clear` (inline/file), `blindfold`, `vault` (deprecated note), `existing` (incl. Venafi/XC-managed → `scripts/xc-managed-cert.md`), with the required variables for each.
- **Inputs** — the variables table from the spec.
- **Outputs** — list from Task 10.
- **Usage** — minimal `module` block + auth env vars.
- **Testing** — `terraform fmt -check -recursive`, `terraform validate`, `terraform test` (explain `mock_provider`, no creds needed).
- **Notes** — namespaces not created; `advertise_mode = "public_ip"` needs a pre-existing Public IP object named `<name_prefix>-public-ip` in `shared`.

- [ ] **Step 2: Write `terraform.tfvars.example`** (root)

```hcl
app_namespace = "my-app-ns"
domains       = ["www.example.com"]

origin_servers = [
  { type = "dns", value = "origin.example.com" },
]

certificate_mode = "clear"
# Provide via TF_VAR_* env vars:
# certificate_pem = "..."
# private_key_pem = "..."

waf_enforcement = "blocking"
advertise_mode  = "public_default_vip"
```

- [ ] **Step 3: Write `CLAUDE.md`**

Content:
- One-paragraph project description.
- Layout map (the File Structure table).
- Conventions: module declares providers only (no provider block); examples hold provider config; secrets via env vars; `string:///${base64encode(...)}` for secret material; namespaces not created.
- How to test: `terraform fmt -check -recursive && terraform validate && terraform test`.
- Provider doc source: `https://registry.terraform.io/providers/volterraedge/volterra/latest/docs` and the GitHub `docs/resources/` markdown.
- Pointer to spec and this plan under `docs/superpowers/`.

- [ ] **Step 4: Validate and final full check**

Run:
```bash
terraform fmt -check -recursive && terraform validate && terraform test
```
Expected: clean, valid, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add README.md CLAUDE.md terraform.tfvars.example
git commit -m "docs: top-level README, CLAUDE.md, and tfvars example"
```

---

## Self-Review

**1. Spec coverage:**
- App firewall / service policy in shared → Task 6. ✓
- Health check in app ns → Task 7. ✓
- Origin pool (DNS/IP list), health check attached → Task 7. ✓
- HTTPS LB with custom cert, WAF, policy, pool → Task 8. ✓
- Certificate switch (clear/blindfold/vault/existing) + inline/file sources → Tasks 3, 4, 5. ✓
- Venafi/Sectigo = existing + API doc → Tasks 11 (existing-ref), 12. ✓
- Cert default namespace `shared` → variable default (Task 3) + locals (Task 4). ✓
- Redirect + HSTS default on → variables (Task 2) + LB (Task 8). ✓
- Single module + examples structure → Tasks 1–13. ✓
- Error handling (validation + preconditions) → Tasks 2, 3, 5. ✓
- Testing (fmt/validate/mock_provider test) → Task 9 + per-task validate steps. ✓
- Defaults (plaintext origin, port 80, public VIP, blocking, allow-all) → Tasks 2, 7, 8. ✓

**2. Placeholder scan:** No "TBD"/"add error handling"/"similar to Task N". Code blocks are concrete. The two documented provider-version uncertainties (list-vs-scalar for `endpoint_selection`/`loadbalancer_algorithm`; `http_redirect`/`add_hsts` placement; test index paths) are written as **explicit resolve-at-validate instructions with a concrete fallback**, not open questions — Terraform's provider schema is the authority and `terraform validate` is the deterministic check.

**3. Type consistency:** `local.cert_ref_name`/`local.cert_ref_namespace`, `local.create_certificate`, `local.cert_name`, `local.names.*` are defined in Task 4 and used consistently in Tasks 5, 8, 10. `volterra_certificate.this` is `count`-gated throughout (`[0]`, `length(...)`). Variable names match between `variables.tf` (Tasks 2–3), resources (Tasks 5–8), tests (Task 9), and examples (Task 11).

**4. Review Focus:** Each of the five items has an owning test in Task 9 — existing-mode-ignores-stray-PEM (`existing_mode_no_cert`), inline-vs-file precedence (`inline_beats_file`), mixed origins (`mixed_origins`) + invalid origin type (`invalid_origin_type_rejected`), clear-missing-material precondition (`clear_missing_material_fails`), and out-of-range enum (`invalid_waf_mode_rejected`). ✓
