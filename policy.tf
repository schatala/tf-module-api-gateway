data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  # Hardcoded CIDR allowlists — edit to your real values.
  ip_whitelist_production = [
    "184.72.69.228/32",
    "34.235.8.28/32",
    "107.22.231.91/32"
  ]

  ip_whitelist_nonproduction = [
    "34.198.225.1/32",
    "54.221.87.192/32",
    "3.222.223.37/32",
    "18.210.200.207/32",
    "54.145.132.232/32",
    "34.236.28.139/32",
    # --- SOAP API consumer IPs - replace with your actual IPs ---
    "3.217.110.156/32",
  ]

  selected_whitelist = var.is_production ? local.ip_whitelist_production : local.ip_whitelist_nonproduction

  # Use wildcard API id to avoid a cycle between the policy doc and the REST API resource.
  execute_api_resource_wildcard = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*/*/*/*"
}

data "aws_iam_policy_document" "rest_api_policy" {
  statement {
    sid    = "DenyNotWhitelisted"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["execute-api:Invoke"]
    resources = [local.execute_api_resource_wildcard]

    condition {
      test     = "NotIpAddress"
      variable = "aws:SourceIp"
      values   = local.selected_whitelist
    }
  }

  statement {
    sid    = "AllowInvoke"
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["execute-api:Invoke"]
    resources = [local.execute_api_resource_wildcard]
  }
}
