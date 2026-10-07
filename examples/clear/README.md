# Example: clear (local folder)

Deploys the app-delivery stack with the TLS private key supplied **unencrypted** from a
local folder. Simplest path — good for demos and lab tenants.

> The key is sent to F5XC as clear material and is stored in Terraform state. For
> production, prefer the [`blindfold`](../blindfold) example, which encrypts the key
> offline so it never appears in plaintext in state.

## Certificate folder

`certificate_mode = "clear"` with `cert_dir` pointing at a folder that contains, by
convention:

| File | Required | Purpose |
|---|---|---|
| `cert.pem` | yes | Leaf certificate |
| `key.pem` | yes | Unencrypted private key |
| `chain.pem` | no | Intermediate chain (appended after the leaf) |

```bash
mkdir -p certs
cp /path/to/your/cert.pem  certs/cert.pem
cp /path/to/your/key.pem   certs/key.pem
# optional: cp /path/to/chain.pem certs/chain.pem
```

## Required inputs

| Input | How |
|---|---|
| `VES_P12_PASSWORD` | env var — password for the API P12 file |
| `api_p12_file`, `api_url` | in `terraform.tfvars` |
| `cert_dir` contents | place `cert.pem` / `key.pem` in `./certs` |

## Run

```bash
export VES_P12_PASSWORD=...
cp terraform.tfvars.example terraform.tfvars   # set api_p12_file, api_url
terraform init
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```
