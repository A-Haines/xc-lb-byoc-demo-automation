# Example: blindfold (local folder)

Deploys the app-delivery stack with a **Blindfold**-encrypted private key — the
F5XC-recommended approach. The key is encrypted **offline before `apply`**, so the
plaintext key never reaches F5XC and never appears in Terraform state.

## Why the key is encrypted offline (not in Terraform)

Blindfold is **client-side** encryption: you fetch your tenant's public key and encrypt
the private key *on your machine*, so only ciphertext is ever sent to or stored in F5XC.
There is **no Terraform-native or API way to do this at `apply` time** — by design:

- The `volterra` provider's `blindfold_secret_info` block takes only a **pre-computed**
  `location` string; it does not encrypt anything.
- The XC API exposes only *unseal* (decrypt), never a server-side *encrypt* — a
  server-side "encrypt my plaintext" call would defeat the point of Blindfold.

So you run `vesctl` once to produce the blindfolded value, save it to
`certs/key.blindfold`, and the module passes it through verbatim as the key `location`.

## Certificate folder

`certificate_mode = "blindfold"` with `cert_dir` pointing at a folder that contains, by
convention:

| File | Required | Purpose |
|---|---|---|
| `cert.pem` | yes | Leaf certificate |
| `key.blindfold` | yes | Offline-encrypted key location (`string:///<blob>`) |
| `chain.pem` | no | Intermediate chain (appended after the leaf) |

## Step 1 — Install `vesctl`

Download the latest binary from the official releases
(<https://gitlab.com/volterra.io/vesctl/-/releases>) and put it on your `PATH`:

```bash
# macOS (darwin); for Linux swap darwin-amd64 → linux-amd64
curl -LO "https://vesio.azureedge.net/releases/vesctl/$(curl -s https://downloads.volterra.io/releases/vesctl/latest.txt)/vesctl.darwin-amd64.gz"
gzip -d vesctl.darwin-amd64.gz
chmod +x vesctl.darwin-amd64
sudo mv vesctl.darwin-amd64 /usr/local/bin/vesctl

vesctl version   # verify
```

## Step 2 — Point `vesctl` at your tenant

`vesctl` uses the **same API P12 credential** as the Terraform provider. Create
`~/.vesconfig` and export the P12 password:

```yaml
# ~/.vesconfig
server-urls: https://my-tenant.console.ves.volterra.io/api
p12-bundle:  /path/to/api_credential.p12
```

```bash
export VES_P12_PASSWORD='<your-p12-password>'
```

## Step 3 — Blindfold the key

Fetch the tenant public key and the secret policy, then encrypt. **All three steps are
required** — `--public-key` is not optional:

```bash
mkdir -p certs
cp /path/to/your/cert.pem certs/cert.pem        # leaf cert
# optional: cp /path/to/chain.pem certs/chain.pem

# 3a. Tenant public key (encrypts for your tenant)
vesctl request secrets get-public-key > pubkey

# 3b. Secret policy — who is allowed to decrypt (default: allow F5XC to use the secret)
vesctl request secrets get-policy-document --namespace shared --name ves-io-allow-volterra > policy

# 3c. Encrypt the private key → certs/key.blindfold
# (pipe through tail -1 to strip the header line vesctl prints)
vesctl request secrets encrypt --policy-document policy --public-key pubkey /path/to/key.pem | tail -1 > certs/key.blindfold
```

`certs/key.blindfold` now holds a `string:///<base64>` value; the module reads it and
passes it to the certificate's `blindfold_secret_info.location`. The plaintext `key.pem`
stays on your machine — do not copy it into `certs/`.

> **Policy note:** `ves-io-allow-volterra` in `shared` is the built-in policy that lets
> the F5XC platform use the secret — the right default for serving TLS on a load
> balancer. To restrict decryption further, create a `volterra_secret_policy` and pass
> its namespace/name to `get-policy-document` instead.

## Required inputs

| Input | How |
|---|---|
| `VES_P12_PASSWORD` | env var — password for the API P12 file (used by both `vesctl` and Terraform) |
| `api_p12_file`, `api_url` | in `terraform.tfvars` |
| `cert_dir` contents | `cert.pem` + `key.blindfold` in `./certs` (optional `chain.pem`) |

## Step 4 — Deploy

```bash
cp terraform.tfvars.example terraform.tfvars   # set api_p12_file, api_url
terraform init
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```
