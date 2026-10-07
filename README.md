# F5 Distributed Cloud - Bring Your Own Certificate Load Balancer Terraform Package

Terraform module that deploys a HTTPS Load Balancer in F5 Distributed Cloud (XC) with 
one `terraform apply`. The TLS certificate is supplied from a **local folder** — 
point `cert_dir` at a directory of PEM files and the module does the rest.

## Quick Start

You need: Terraform ≥ 1.5, an F5XC API **P12 file + password**, and an **existing app 
namespace** in your tenant.

```bash
# 1. Clone and enter the repo
git clone <repo-url>
cd xc-lb-byoc-demo-automation

# 2. Drop your TLS files into ./certs (clear mode = plaintext key; fine for a demo)
mkdir -p certs
cp /path/to/cert.pem certs/cert.pem
cp /path/to/key.pem  certs/key.pem

# 3. Configure your variables (see "Configuring Variables" below)
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 4. Set the P12 password
export VES_P12_PASSWORD='<your-p12-password>'

# 5. Deploy
terraform init && terraform apply
```

## Configuring Variables

The easiest way to configure this module is with a `terraform.tfvars` file. Copy the 
example and fill in your values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then edit `terraform.tfvars`:

```hcl
# Required: F5 XC API credentials
xc_api_p12_file = "/path/to/your-tenant.console.ves.volterra.io.api-creds.p12"
xc_api_url      = "https://your-tenant.console.ves.volterra.io/api"

# Required: Application configuration
app_namespace   = "my-app-ns"      # Must already exist in your tenant
name_prefix     = "demo"           # Prefix for all created resources
domains         = "www.example.com"
origin_servers  = "origin.example.com"
```

### All Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `xc_api_p12_file` | yes | — | Path to F5 XC API P12 certificate file |
| `xc_api_url` | yes | — | F5 XC API URL (e.g. `https://<tenant>.console.ves.volterra.io/api`) |
| `app_namespace` | yes | — | Existing F5XC namespace for resources |
| `name_prefix` | yes | — | Prefix for all created resource names |
| `domains` | yes | — | Domain served by the load balancer |
| `origin_servers` | yes | — | Public DNS name of the origin server |
| `origin_port` | no | `80` | TCP port on the origin server |
| `origin_use_tls` | no | `false` | Connect to origin over TLS |
| `waf_enforcement` | no | `monitoring` | WAF mode: `blocking` or `monitoring` |
| `certificate_mode` | no | `clear` | Key mode: `clear` or `blindfold` |
| `cert_dir` | no | `./certs` | Path to folder with TLS material |

> **Note:** When entering paths at an interactive prompt, do **not** include quotes around 
> the value. Use `terraform.tfvars` to avoid interactive prompt issues.

`terraform apply` prints the load balancer domain. Point DNS at the XC VIP and you're
live. For production (key never in plaintext) use [`blindfold`](examples/blindfold/)
instead — same steps plus one offline `vesctl` encrypt.

## What it deploys

| Resource | Provider resource | Namespace |
|---|---|---|
| App Firewall (WAF) | `volterra_app_firewall` | `shared` |
| Service Policy | `volterra_service_policy` | `shared` |
| Certificate | `volterra_certificate` | `shared` (default) |
| HTTP Health Check | `volterra_healthcheck` | `var.app_namespace` |
| Origin Pool | `volterra_origin_pool` | `var.app_namespace` |
| HTTPS Load Balancer | `volterra_http_loadbalancer` | `var.app_namespace` |

The load balancer applies the WAF and service policy from `shared`, routes to the
health-checked origin pool, serves HTTPS with your certificate, and (by default)
redirects HTTP→HTTPS with HSTS enabled.

## Requirements

- Terraform **>= 1.7**.
- Provider `volterraedge/volterra` **~> 0.13** (developed against 0.13.2).
- An existing `shared` namespace (built in) and an existing `var.app_namespace`.
  **This module does not create namespaces.**
- F5XC API credentials (P12 file + URL, or cert/key + URL).

## Certificate: local folder

Put your TLS material in one folder and point `cert_dir` at it. The module reads these
files **by convention**:

| File | Required | Purpose |
|---|---|---|
| `cert.pem` | yes | Leaf certificate |
| `chain.pem` | no | Intermediate chain (appended after the leaf) |
| `key.pem` | `clear` mode | Unencrypted private key |
| `key.blindfold` | `blindfold` mode | Offline-encrypted key location (`string:///<blob>`) |

`certificate_mode` picks how the private key is supplied:

| Mode | What it does | Key file | Example |
|---|---|---|---|
| `clear` | Creates a certificate with an unencrypted key. Key lands in TF state — good for demos/labs. | `key.pem` | [`clear`](examples/clear/) |
| `blindfold` | Creates a certificate with a Blindfold-encrypted key (key never plaintext in state). **Recommended.** | `key.blindfold` | [`blindfold`](examples/blindfold/) |

When `chain.pem` is present the intermediate chain is appended to the leaf certificate
(required by most public CAs, e.g. Sectigo).

For `blindfold`, encrypt the key offline first with `vesctl` and save the result to
`key.blindfold` (blindfold is client-side only — it cannot be done in Terraform or the
XC API). All three steps are required:

```bash
vesctl request secrets get-public-key > pubkey
vesctl request secrets get-policy-document --namespace shared --name ves-io-allow-volterra > policy
vesctl request secrets encrypt --policy-document policy --public-key pubkey key.pem | tail -1 > certs/key.blindfold
```

See [`examples/blindfold`](examples/blindfold/) for `vesctl` install and full steps.

## Usage

```hcl
module "app_delivery" {
  source = "github.com/<org>/epsilon-demo-automation" # or a local path

  app_namespace = "my-app-ns"
  domains       = ["www.example.com"]

  origin_servers = ["origin.example.com"]

  certificate_mode = "blindfold"
  cert_dir         = "${path.module}/certs" # holds cert.pem + key.blindfold
}
```

Provider credentials live in **your** root config, not the module:

```hcl
provider "volterra" {
  api_p12_file = "/path/to/api_credential.p12"
  url          = "https://my-tenant.console.ves.volterra.io/api"
  # password via VES_P12_PASSWORD env var
}
```

## Outputs

`load_balancer_name`, `load_balancer_domains`, `certificate_id`,
`certificate_reference` (`{name, namespace}`), `origin_pool_name`, `app_firewall_name`,
`service_policy_name`.

## Notes

- In `clear` mode the private key is stored in Terraform state. Prefer `blindfold` for
  anything beyond demos/labs.
