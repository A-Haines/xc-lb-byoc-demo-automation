# Example: clear-file

Deploys the app-delivery stack with a **clear** certificate read from local PEM
files via Terraform's `file()`. This example also shows a **Public IP** origin.

## Certificate path

`certificate_mode = "clear"` with `certificate_file` / `private_key_file` pointing
at `cert.pem` and `key.pem` in this directory. As with any clear mode, the key is
stored unencrypted in F5XC and appears in Terraform state.

## Required inputs

| Input | How |
|---|---|
| `VES_P12_PASSWORD` | env var — password for the API P12 file |
| `api_p12_file`, `api_url` | in `terraform.tfvars` |
| `cert.pem`, `key.pem` | files placed in this directory (git-ignored) |

## Run

```bash
export VES_P12_PASSWORD=...
# place cert.pem and key.pem here
cp terraform.tfvars.example terraform.tfvars   # edit api_p12_file / api_url
terraform init
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```
