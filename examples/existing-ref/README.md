# Example: existing-ref

Deploys the app-delivery stack referencing a **certificate that already exists** in
the tenant. Terraform creates no certificate object — it only points the load
balancer at one by name and namespace.

## When to use this

Two situations map to this mode:

1. **Pre-provisioned custom certificate** — a cert uploaded or managed outside this
   Terraform package.
2. **XC-managed certificate (Sectigo CA → Venafi → F5 Distributed Cloud)** — F5XC's
   Certificate Management integrates with a CA (e.g. Sectigo via Venafi) and
   issues/auto-renews a managed certificate object. The `volterraedge/volterra`
   provider has **no resource** for that issuance flow, so Terraform references the
   resulting cert by name. See [`scripts/xc-managed-cert.md`](../../scripts/xc-managed-cert.md).

## Certificate path

`certificate_mode = "existing"` with `existing_certificate_name` /
`existing_certificate_namespace`. The named certificate must already exist in the
tenant before `apply`.

## Required inputs

| Input | How |
|---|---|
| `VES_P12_PASSWORD` | env var — password for the API P12 file |
| `api_p12_file`, `api_url` | in `terraform.tfvars` |
| `existing_certificate_name`, `existing_certificate_namespace` | set in `main.tf` |

## Run

```bash
export VES_P12_PASSWORD=...
cp terraform.tfvars.example terraform.tfvars   # edit api_p12_file / api_url
terraform init
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```
