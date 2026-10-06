# CLAUDE.md

Guidance for Claude Code (and other agents) working in this repository.

## What this is

A lean, reusable Terraform **module** that deploys an HTTPS application-delivery stack
in F5 Distributed Cloud (XC): App Firewall + Service Policy in `shared`; Health Check,
Origin Pool, and HTTPS Load Balancer in a variable-defined app namespace. Its defining
feature is customer-selectable TLS certificate handling (`certificate_mode` =
`clear` | `blindfold` | `vault` | `existing`).

## Layout

| Path | Responsibility |
|---|---|
| `versions.tf` | `required_version` + `required_providers` (volterra `~> 0.13`). No provider block. |
| `variables.tf` | All inputs + `validation` blocks. |
| `locals.tf` | PEM source resolution, cert-reference selection, resource names. |
| `certificate.tf` | Single `count`-gated `volterra_certificate` with `dynamic` secret blocks + preconditions. |
| `main.tf` | The five non-certificate resources (shared: WAF, policy; app ns: healthcheck, pool, LB). |
| `outputs.tf` | Module outputs. |
| `examples/*/` | One runnable root per certificate mode. |
| `scripts/xc-managed-cert.md` | XC Certificate Management (Venafi/Sectigo) flow — the `existing` story. |
| `tests/*.tftest.hcl` | Native `terraform test` with `mock_provider` (no creds). |
| `docs/superpowers/` | Design spec and implementation plan. |

## Conventions

- **The module declares providers only — never a `provider` block.** Each `examples/`
  root supplies its own `provider "volterra"` with credentials. Keep it that way so the
  module stays portable.
- **Secrets never hardcoded.** Certificate/key material comes from sensitive variables
  (prefer `TF_VAR_*` env vars) or `file()`. The API P12 password comes from
  `VES_P12_PASSWORD`.
- **Secret material format:** `"string:///${base64encode(pem)}"` for `certificate_url`
  and `clear_secret_info.url`.
- **Certificate referencing:** the LB always references a cert by
  `local.cert_ref_name` / `local.cert_ref_namespace`, which resolve to the created cert
  (clear/blindfold/vault) or the existing one (`existing` mode). Don't reference
  `volterra_certificate.this` directly outside `outputs.tf` — it is `count`-gated.
- **Namespaces are not created here.** `shared` is built in; the app namespace must
  pre-exist.

## How to test

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate      # one benign deprecation warning on default_bot_setting (see README)
terraform test          # mock_provider plan assertions, no tenant needed
```

When changing resource HCL, confirm attribute/block shapes against the installed
provider with `terraform providers schema -json` rather than guessing.

## References

- Provider docs: <https://registry.terraform.io/providers/volterraedge/volterra/latest/docs>
  and the source markdown under `docs/resources/` in
  `volterraedge/terraform-provider-volterra` (branch `main`).
- Design spec: `docs/superpowers/specs/2026-10-06-f5xc-app-delivery-package-design.md`
- Implementation plan: `docs/superpowers/plans/2026-10-06-f5xc-app-delivery-package.md`
