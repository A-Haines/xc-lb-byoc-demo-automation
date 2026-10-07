# F5 Distributed Cloud App-Delivery Terraform Package

A lean, reusable Terraform module that deploys a complete HTTPS application-delivery
stack in F5 Distributed Cloud (XC) with one `terraform apply`. The TLS certificate is
supplied from a **local folder** — point `cert_dir` at a directory of PEM files and the
module does the rest.

## 🚀 Quick start — deploy in 5 steps

Fastest path uses the [`clear`](examples/clear/) example. You need: Terraform ≥ 1.7, an
F5XC API **P12 file + password**, and an **existing app namespace** in your tenant.

```bash
# 1. Go to the ready-made example root
cd examples/clear

# 2. Drop your TLS files into ./certs  (clear mode = plaintext key; fine for a demo)
mkdir -p certs
cp /path/to/cert.pem certs/cert.pem
cp /path/to/key.pem  certs/key.pem

# 3. Point at your tenant + P12
cp terraform.tfvars.example terraform.tfvars   # then edit api_p12_file and api_url
export VES_P12_PASSWORD='<your-p12-password>'

# 4. Edit the three app lines in main.tf: app_namespace (MUST already exist in your
#    tenant — the module does not create it), domains, origin_servers

# 5. Ship it
terraform init && terraform apply -var-file=terraform.tfvars
```

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
vesctl request secrets encrypt --policy-document policy --public-key pubkey key.pem > certs/key.blindfold
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

## Inputs

| Variable | Default | Purpose |
|---|---|---|
| `app_namespace` | — (required) | Namespace for health check / pool / LB |
| `name_prefix` | `"epsilon"` | Prefix for created resource names |
| `domains` | `["www.auto-test.cloud.myf5demo.com"]` | LB domains (non-empty) |
| `origin_servers` | `["ah-digital-azure.azurewebsites.net"]` | Public DNS names of the origin servers |
| `origin_port` | `80` | Origin port |
| `origin_use_tls` | `false` | TLS to origin |
| `origin_tls_skip_verification` | `false` | Skip origin cert verification (insecure; default verifies against the Volterra trusted CA) |
| `health_check_path` | `"/"` | HTTP health check path |
| `health_check_status_codes` | `["200"]` | Expected status codes |
| `healthy_threshold` / `unhealthy_threshold` | `2` / `3` | Health thresholds |
| `health_interval` / `health_timeout` | `10` / `3` | Health timing (seconds) |
| `waf_enforcement` | `"blocking"` | `blocking` or `monitoring` |
| `service_policy_action` | `"allow_all"` | `allow_all` or `deny_all` |
| `advertise_mode` | `"public_default_vip"` | `public_default_vip`, `public_ip`, or `do_not_advertise` |
| `enable_http_redirect` | `true` | HTTP→HTTPS redirect |
| `enable_hsts` | `true` | HSTS header |
| `certificate_mode` | `"clear"` | `clear` or `blindfold` |
| `cert_dir` | — (required) | Local folder holding `cert.pem`, optional `chain.pem`, and `key.pem`/`key.blindfold` |
| `certificate_name` | `"<name_prefix>-cert"` | Created cert name |
| `certificate_namespace` | `"shared"` | Created cert namespace |

## Outputs

`load_balancer_name`, `load_balancer_domains`, `certificate_id`,
`certificate_reference` (`{name, namespace}`), `origin_pool_name`, `app_firewall_name`,
`service_policy_name`.

## Checking the configuration

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate      # one benign deprecation warning on default_bot_setting (see Notes)
```

## Notes

- **Namespaces are not created** by this module; `var.app_namespace` must pre-exist.
- `advertise_mode = "public_ip"` references a Public IP object named
  `<name_prefix>-public-ip` in `shared` that must pre-exist.
- The App Firewall emits a provider **deprecation warning** on `default_bot_setting`.
  The bot-protection setting is a required choice whose only options are both
  provider-deprecated in v0.13.x, so the warning is unavoidable and benign; `validate`
  still succeeds.
- In `clear` mode the private key is stored in Terraform state. Prefer `blindfold` for
  anything beyond demos/labs.
