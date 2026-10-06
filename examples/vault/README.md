# Example: vault

Deploys the app-delivery stack with the private key sourced from **HashiCorp Vault**
at runtime via F5XC's Vault secret integration.

> **Deprecation note:** `vault_secret_info` is marked **deprecated** in the
> `volterraedge/volterra` provider (v0.13.x). It still functions, but prefer
> `blindfold` (or `clear`) for new deployments. This example is provided for
> completeness.

## Certificate path

`certificate_mode = "vault"` with `certificate_pem` (the public cert),
`vault_key_location` (the Vault path to the key), and `vault_provider` (the name of a
Secret Management Access object that integrates Vault in your tenant). Set up the SMA
object in the F5XC console before running.

## Required inputs

| Input | How |
|---|---|
| `VES_P12_PASSWORD` | env var — password for the API P12 file |
| `api_p12_file`, `api_url` | in `terraform.tfvars` |
| `certificate_pem` | `TF_VAR_certificate_pem` env var |
| `vault_key_location`, `vault_provider` | set in `main.tf` (edit for your Vault) |

## Run

```bash
export VES_P12_PASSWORD=...
export TF_VAR_certificate_pem="$(cat cert.pem)"
cp terraform.tfvars.example terraform.tfvars   # edit api_p12_file / api_url
terraform init
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```
