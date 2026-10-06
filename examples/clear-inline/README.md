# Example: clear-inline

Deploys the app-delivery stack with a **clear** certificate supplied via inline
sensitive variables (no files on disk).

## Certificate path

`certificate_mode = "clear"` with `certificate_pem` / `private_key_pem` passed as
Terraform variables. The private key is stored as a clear (unencrypted) secret in
F5XC and therefore also appears in Terraform state — keep state secured. For a
key that never lands in plaintext, use the `blindfold` example instead.

## Required inputs

| Input | How |
|---|---|
| `VES_P12_PASSWORD` | env var — password for the API P12 file |
| `api_p12_file`, `api_url` | in `terraform.tfvars` |
| `certificate_pem`, `private_key_pem` | `TF_VAR_*` env vars (recommended) or `terraform.tfvars` |

## Run

```bash
export VES_P12_PASSWORD=...
export TF_VAR_certificate_pem="$(cat cert.pem)"
export TF_VAR_private_key_pem="$(cat key.pem)"

cp terraform.tfvars.example terraform.tfvars   # edit api_p12_file / api_url
terraform init
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```
