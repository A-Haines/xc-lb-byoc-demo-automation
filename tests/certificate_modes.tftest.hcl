mock_provider "volterra" {}

variables {
  app_namespace  = "app-ns"
  domains        = ["www.example.com"]
  origin_servers = [{ type = "dns", value = "origin.example.com" }]
}

# clear mode (inline) creates exactly one certificate
run "clear_mode_creates_cert" {
  command = plan
  variables {
    certificate_mode = "clear"
    certificate_pem  = "-----BEGIN CERTIFICATE-----\nX\n-----END CERTIFICATE-----"
    private_key_pem  = "-----BEGIN PRIVATE KEY-----\nY\n-----END PRIVATE KEY-----"
  }
  assert {
    condition     = length(volterra_certificate.this) == 1
    error_message = "clear mode must create exactly one certificate"
  }
  assert {
    condition     = volterra_http_loadbalancer.this.https[0].tls_cert_params[0].certificates[0].name == local.cert_name
    error_message = "LB must reference the created certificate by name"
  }
}

# file source resolves when inline is empty
run "clear_mode_from_files" {
  command = plan
  variables {
    certificate_mode = "clear"
    certificate_file = "tests/fixtures/cert.pem"
    private_key_file = "tests/fixtures/key.pem"
  }
  assert {
    condition     = length(volterra_certificate.this) == 1
    error_message = "clear mode via files must create one certificate"
  }
}

# inline precedence over file
run "inline_beats_file" {
  command = plan
  variables {
    certificate_mode = "clear"
    certificate_pem  = "-----BEGIN CERTIFICATE-----\nINLINE\n-----END CERTIFICATE-----"
    private_key_pem  = "-----BEGIN PRIVATE KEY-----\nINLINE\n-----END PRIVATE KEY-----"
    certificate_file = "tests/fixtures/cert.pem"
    private_key_file = "tests/fixtures/key.pem"
  }
  assert {
    condition     = local.cert_pem == "-----BEGIN CERTIFICATE-----\nINLINE\n-----END CERTIFICATE-----"
    error_message = "inline PEM must take precedence over file"
  }
}

# existing mode creates zero certificates and references the existing one
run "existing_mode_no_cert" {
  command = plan
  variables {
    certificate_mode          = "existing"
    certificate_pem           = "-----BEGIN CERTIFICATE-----\nSTRAY\n-----END CERTIFICATE-----"
    existing_certificate_name = "preprovisioned-cert"
  }
  assert {
    condition     = length(volterra_certificate.this) == 0
    error_message = "existing mode must create zero certificates even if cert PEM is set"
  }
  assert {
    condition     = volterra_http_loadbalancer.this.https[0].tls_cert_params[0].certificates[0].name == "preprovisioned-cert"
    error_message = "existing mode must reference existing_certificate_name"
  }
}

# blindfold mode
run "blindfold_mode" {
  command = plan
  variables {
    certificate_mode       = "blindfold"
    certificate_pem        = "-----BEGIN CERTIFICATE-----\nX\n-----END CERTIFICATE-----"
    blindfold_key_location = "string:///blindfolded"
  }
  assert {
    condition     = length(volterra_certificate.this) == 1
    error_message = "blindfold mode must create one certificate"
  }
}

# mixed dns/ip origins both map
run "mixed_origins" {
  command = plan
  variables {
    certificate_mode          = "existing"
    existing_certificate_name = "c"
    origin_servers = [
      { type = "dns", value = "a.example.com" },
      { type = "ip", value = "203.0.113.10" },
    ]
  }
  assert {
    condition     = length(volterra_origin_pool.this.origin_servers) == 2
    error_message = "both origin servers must be present"
  }
}

# clear mode missing material fails precondition
run "clear_missing_material_fails" {
  command         = plan
  expect_failures = [volterra_certificate.this]
  variables {
    certificate_mode = "clear"
  }
}

# invalid enum rejected by variable validation
run "invalid_waf_mode_rejected" {
  command         = plan
  expect_failures = [var.waf_enforcement]
  variables {
    certificate_mode          = "existing"
    existing_certificate_name = "c"
    waf_enforcement           = "bogus"
  }
}

# invalid origin type rejected
run "invalid_origin_type_rejected" {
  command         = plan
  expect_failures = [var.origin_servers]
  variables {
    certificate_mode          = "existing"
    existing_certificate_name = "c"
    origin_servers            = [{ type = "ftp", value = "x" }]
  }
}
