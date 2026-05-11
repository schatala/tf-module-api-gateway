variable "name" {
  type        = string
  description = "API name."
}

variable "stage_name" {
  type        = string
  description = "Stage name for the REST API. REST APIs require a stage."
  default     = "default"
}

variable "is_production" {
  type        = bool
  description = "If true, apply the production IP whitelist; otherwise apply the non-production whitelist."
}

variable "jwt_audience" {
  type        = list(string)
  description = "Accepted JWT audiences."
  default     = ["api://585f3a95-8bf5-4df4-b80b-585ca5ca2071"]
}

variable "routes" {
  description = <<EOT
Minimal backend lambda route definitions.
Example:
[
  { path = "/health", method = "GET",  lambda_arn = "arn:aws:lambda:..." },
  { path = "/users",  method = "POST", lambda_arn = "arn:aws:lambda:..." }
]
EOT

  type = list(object({
    path       = string
    method     = string
    lambda_arn = string
  }))
}

# ---------------------------------------------------------------------------
# Optional — when set, this list is used instead of the shared prod/non-prod
# lists, giving each API gateway its own independent IP allowlist.
# The existing api_gateway call never passes this so it is completely
# unaffected and keeps using ip_whitelist_nonproduction as before.
# ---------------------------------------------------------------------------
variable "custom_ip_whitelist" {
  type        = list(string)
  description = "Explicit CIDR allowlist for this API. Overrides the shared prod/non-prod lists when provided. Leave null to use the shared lists."
  default     = null
}

# ---------------------------------------------------------------------------
# mTLS / custom domain — all three default to null so existing callers
# (e.g. the existing api_gateway block pinned at v1.0.0) are completely
# unaffected.  Set these only when you are ready to enable the custom domain
# and mTLS.
# ---------------------------------------------------------------------------

variable "domain_name" {
  type        = string
  description = "Custom domain name for the API (e.g. soap-api.mvsolutions.com). Leave null to skip custom domain and mTLS setup."
  default     = null
}

variable "regional_certificate_arn" {
  type        = string
  description = "ACM certificate ARN for the custom domain (TLS). Required when domain_name is set."
  default     = null
}

variable "mtls_truststore_uri" {
  type        = string
  description = "S3 URI of the mTLS truststore PEM bundle (e.g. s3://my-bucket/truststore.pem). Required when domain_name is set and mTLS is needed."
  default     = null
}
