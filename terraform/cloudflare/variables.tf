# Identifiers, not secrets. The import blocks need the IDs of what already exists.

variable "account_id" {
  type = string
}

variable "zone_id" {
  description = "quantaid.org's zone"
  type        = string
}

variable "tunnel_id" {
  description = "quantaid-selfhost's ID, the <id> in the CNAMEs' <id>.cfargotunnel.com"
  type        = string
}

variable "apex_record_id" {
  description = "The quantaid.org CNAME's record ID"
  type        = string
}

variable "www_record_id" {
  description = "The www.quantaid.org CNAME's record ID"
  type        = string
}

variable "rate_limit_ruleset_id" {
  description = "The zone's http_ratelimit ruleset ID"
  type        = string
}
