# Example: blindfold

Deploys the app-delivery stack with a **Blindfold**-encrypted private key — the
F5XC-recommended approach. The key is encrypted offline before `apply`, so it never
appears in plaintext in Terraform state.

## Certificate path

`certificate_mode = "blindfold"` with `certificate_pem` (the public cert) and
`blindfold_key_location` (the encrypted key reference). Blindfold the key first with
`vesctl`:

```bash
vesctl request secrets encrypt --policy-document policy.json key.pem
```

The command prints the blindfolded value; pass it as `blindfold_key_location`
(typically `string:///<base64>`).

## Required inputs

| Input | How |
|---|---|
| `VES_P12_PASSWORD` | env var — password for the API P12 file |
| `api_p12_file`, `api_url` | in `terraform.tfvars` |
| `certificate_pem` | `TF_VAR_certificate_pem` env var |
| `blindfold_key_location` | in `terraform.tfvars` |

## Run

```bash
export VES_P12_PASSWORD=...
export TF_VAR_certificate_pem="$(cat cert.pem)"
cp terraform.tfvars.example terraform.tfvars   # set blindfold_key_location, api_*
terraform init
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```
