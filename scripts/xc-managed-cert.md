# XC-Managed Certificates (Sectigo CA → Venafi → F5 Distributed Cloud)

This guide covers the certificate path where F5 Distributed Cloud (XC) **manages the
certificate itself** — issuing and auto-renewing it through a CA integration (for
example Sectigo, fronted by Venafi) — and the Terraform package simply **references**
the resulting certificate.

## Why this is not a Terraform resource

The `volterraedge/volterra` Terraform provider exposes `volterra_certificate` (a cert
you supply) but has **no resource** for CA-integrated certificate *issuance* — there is
no `volterra_managed_certificate`, Venafi, or ACME issuance resource. XC Certificate
Management is a console/API capability of the platform, not a provider resource.

So in Terraform terms this path **is** the `existing` certificate mode: XC produces a
certificate object in a namespace, and the load balancer references it by name. Set:

```hcl
certificate_mode               = "existing"
existing_certificate_name      = "<name of the XC-managed certificate>"
existing_certificate_namespace = "shared"
```

See [`examples/existing-ref/`](../examples/existing-ref/).

## The model

```
Sectigo CA  ──issues──►  Venafi  ──integration──►  F5 XC Certificate Management
                                                          │
                                                          ▼
                                          Managed Certificate object (a namespace)
                                                          │
                                        referenced by name ▼
                                             volterra_http_loadbalancer  (this module, "existing" mode)
```

## Steps (console)

1. **Configure the CA / Venafi integration** in the XC console under
   **Shared Configuration → Manage → Certificate Management** (exact menu labels vary
   by tenant/version). Provide the Venafi/Sectigo connection details per your
   organization's PKI setup.
2. **Create a managed certificate** for your domain (e.g. `www.example.com`). XC
   requests issuance through the CA and manages renewal automatically.
3. **Note the certificate's name and namespace.** This is what the load balancer
   references.
4. **Reference it from Terraform** using `certificate_mode = "existing"` with
   `existing_certificate_name` / `existing_certificate_namespace`, then
   `terraform apply`.

## Optional: driving it via the XC API

XC exposes a public REST API at `https://<tenant>.console.ves.volterra.io/api/...`.
Certificate Management can be scripted there instead of using the console.

> **Important:** the exact API path and request body for managed-certificate creation
> depend on your tenant's API version and the CA integration in use. Confirm the
> current endpoint against the F5 Distributed Cloud API documentation
> (<https://docs.cloud.f5.com/docs-v2/api/>) before using the skeleton below — it is a
> shape to adapt, not a verified endpoint.

```bash
# Authenticate with your API certificate (same credential as the Terraform provider).
# Replace <tenant>, <namespace>, and the path/body with values from current API docs.
curl --cert api.crt --key api.key \
  -X POST \
  "https://<tenant>.console.ves.volterra.io/api/config/namespaces/<namespace>/certificates" \
  -H "Content-Type: application/json" \
  -d '{
        "metadata": { "name": "www-example-com", "namespace": "<namespace>" },
        "spec": {
          "comment": "Confirm the managed-certificate / CA-integration body against current F5 XC API docs"
        }
      }'
```

## Verify

- The certificate appears in the XC console under **Certificate Management**.
- `certificate_mode = "existing"` in this module references it by name, and
  `terraform plan` shows the load balancer wired to it.
