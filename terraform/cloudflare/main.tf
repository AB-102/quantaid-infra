# quantaid.org's Cloudflare setup. Everything but the cache rule was made in the dashboard before Terraform,
# so each has an import block. They stay after the import: they do nothing once a resource is in the state,
# and they let a lost state be rebuilt with one apply.

# --- The tunnel ---

import {
  to = cloudflare_zero_trust_tunnel_cloudflared.selfhost
  id = "${var.account_id}/${var.tunnel_id}"
}

# Locally managed: its ingress rules are selfhost/ansible/roles/cloudflared/files/config.yml. Every host runs a
# connector of this one tunnel.
resource "cloudflare_zero_trust_tunnel_cloudflared" "selfhost" {
  account_id = var.account_id
  name       = "quantaid-selfhost"
  config_src = "local"

  lifecycle {
    # The API never returns the secret, and every host's token derives from it. Rotating it is a deliberate step.
    ignore_changes = [tunnel_secret]
  }
}

import {
  to = cloudflare_dns_record.apex
  id = "${var.zone_id}/${var.apex_record_id}"
}

resource "cloudflare_dns_record" "apex" {
  zone_id = var.zone_id
  name    = "quantaid.org"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.selfhost.id}.cfargotunnel.com"
  proxied = true
  # Automatic, which proxied records always use
  ttl = 1
}

import {
  to = cloudflare_dns_record.www
  id = "${var.zone_id}/${var.www_record_id}"
}

resource "cloudflare_dns_record" "www" {
  zone_id = var.zone_id
  name    = "www.quantaid.org"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.selfhost.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# --- Protection ---

import {
  to = cloudflare_ruleset.rate_limit
  id = "zones/${var.zone_id}/${var.rate_limit_ruleset_id}"
}

# One address can make 20 AI requests per 10 seconds, then it's blocked for 10 seconds. The free plan allows one rule.
resource "cloudflare_ruleset" "rate_limit" {
  zone_id = var.zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [{
    description = "Rate limit the AI routes"
    expression  = "(starts_with(http.request.uri.path, \"/api/ai/\"))"
    action      = "block"
    ratelimit = {
      # Per IP; the free plan always adds the data center
      characteristics     = ["ip.src", "cf.colo.id"]
      period              = 10
      requests_per_period = 20
      mitigation_timeout  = 10
    }
  }]
}

import {
  to = cloudflare_zone_setting.always_use_https
  id = "${var.zone_id}/always_use_https"
}

resource "cloudflare_zone_setting" "always_use_https" {
  zone_id    = var.zone_id
  setting_id = "always_use_https"
  value      = "on"
}

import {
  to = cloudflare_zone_setting.hsts
  id = "${var.zone_id}/security_header"
}

# 6 months, without preload
resource "cloudflare_zone_setting" "hsts" {
  zone_id    = var.zone_id
  setting_id = "security_header"
  value = {
    strict_transport_security = {
      enabled            = true
      max_age            = 15552000
      include_subdomains = false
      preload            = false
      nosniff            = false
    }
  }
}

# --- Caching ---

# The frontend's hashed files never change, so the edge keeps them as long as nginx allows (a year). Misses aren't
# kept: during a release, one host can briefly lack a file another host already serves.
resource "cloudflare_ruleset" "cache" {
  zone_id = var.zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [{
    description = "Cache /assets/ at the edge, but not errors"
    expression  = "(starts_with(http.request.uri.path, \"/assets/\"))"
    action      = "set_cache_settings"
    action_parameters = {
      cache = true
      edge_ttl = {
        mode = "respect_origin"
        status_code_ttl = [{
          status_code_range = { from = 400, to = 599 }
          # -1 is no-store
          value = -1
        }]
      }
    }
  }]
}
