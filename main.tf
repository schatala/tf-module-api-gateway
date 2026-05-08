terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  # Hardcoded issuer
  jwt_issuer = "https://sts.windows.net/50bb1d9e-7174-4e06-aecd-e87b1b8c211d/"

  routes_by_key = {
    for r in var.routes :
    "${upper(r.method)} ${r.path}" => {
      path       = r.path
      method     = upper(r.method)
      lambda_arn = r.lambda_arn
    }
  }

  # Split every route path into segments
  route_segs_by_path = {
    for r in var.routes :
    r.path => [for s in split("/", trim(r.path, "/")) : s if s != ""]
  }

  # Build ALL intermediate paths for all routes (e.g. /a, /a/b, /a/b/c)
  all_resource_paths = toset(flatten([
    for p, segs in local.route_segs_by_path : [
      for i in range(1, length(segs) + 1) : "/${join("/", slice(segs, 0, i))}"
    ]
  ]))

  # Map full resource path -> segment array
  segs_by_resource_path = {
    for p in local.all_resource_paths :
    p => [for s in split("/", trim(p, "/")) : s if s != ""]
  }

  # Group resource paths by depth (up to depth 6)
  paths_by_depth = {
    1 = [for p, segs in local.segs_by_resource_path : p if length(segs) == 1]
    2 = [for p, segs in local.segs_by_resource_path : p if length(segs) == 2]
    3 = [for p, segs in local.segs_by_resource_path : p if length(segs) == 3]
    4 = [for p, segs in local.segs_by_resource_path : p if length(segs) == 4]
    5 = [for p, segs in local.segs_by_resource_path : p if length(segs) == 5]
    6 = [for p, segs in local.segs_by_resource_path : p if length(segs) == 6]
  }
}

resource "aws_api_gateway_rest_api" "this" {
  name   = var.name
  policy = data.aws_iam_policy_document.rest_api_policy.json
}

locals {
  root_id = aws_api_gateway_rest_api.this.root_resource_id
}

# ----------------------------
# API Gateway Resources (paths)
# Supports paths up to depth 6
# ----------------------------

resource "aws_api_gateway_resource" "path_level_1" {
  for_each = toset(lookup(local.paths_by_depth, 1, []))

  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = local.root_id
  path_part   = local.segs_by_resource_path[each.value][0]
}

resource "aws_api_gateway_resource" "path_level_2" {
  for_each = toset(lookup(local.paths_by_depth, 2, []))

  rest_api_id = aws_api_gateway_rest_api.this.id

  parent_id = aws_api_gateway_resource.path_level_1[
    "/${local.segs_by_resource_path[each.value][0]}"
  ].id

  path_part = local.segs_by_resource_path[each.value][1]
}

resource "aws_api_gateway_resource" "path_level_3" {
  for_each = toset(lookup(local.paths_by_depth, 3, []))

  rest_api_id = aws_api_gateway_rest_api.this.id

  parent_id = aws_api_gateway_resource.path_level_2[
    "/${join("/", slice(local.segs_by_resource_path[each.value], 0, 2))}"
  ].id

  path_part = local.segs_by_resource_path[each.value][2]
}

resource "aws_api_gateway_resource" "path_level_4" {
  for_each = toset(lookup(local.paths_by_depth, 4, []))

  rest_api_id = aws_api_gateway_rest_api.this.id

  parent_id = aws_api_gateway_resource.path_level_3[
    "/${join("/", slice(local.segs_by_resource_path[each.value], 0, 3))}"
  ].id

  path_part = local.segs_by_resource_path[each.value][3]
}

resource "aws_api_gateway_resource" "path_level_5" {
  for_each = toset(lookup(local.paths_by_depth, 5, []))

  rest_api_id = aws_api_gateway_rest_api.this.id

  parent_id = aws_api_gateway_resource.path_level_4[
    "/${join("/", slice(local.segs_by_resource_path[each.value], 0, 4))}"
  ].id

  path_part = local.segs_by_resource_path[each.value][4]
}

resource "aws_api_gateway_resource" "path_level_6" {
  for_each = toset(lookup(local.paths_by_depth, 6, []))

  rest_api_id = aws_api_gateway_rest_api.this.id

  parent_id = aws_api_gateway_resource.path_level_5[
    "/${join("/", slice(local.segs_by_resource_path[each.value], 0, 5))}"
  ].id

  path_part = local.segs_by_resource_path[each.value][5]
}

# Build a lookup map: "/full/path" -> resource id
locals {
  resource_id_by_path = merge(
    { "/" = local.root_id },
    { for p in toset(lookup(local.paths_by_depth, 1, [])) : p => aws_api_gateway_resource.path_level_1[p].id },
    { for p in toset(lookup(local.paths_by_depth, 2, [])) : p => aws_api_gateway_resource.path_level_2[p].id },
    { for p in toset(lookup(local.paths_by_depth, 3, [])) : p => aws_api_gateway_resource.path_level_3[p].id },
    { for p in toset(lookup(local.paths_by_depth, 4, [])) : p => aws_api_gateway_resource.path_level_4[p].id },
    { for p in toset(lookup(local.paths_by_depth, 5, [])) : p => aws_api_gateway_resource.path_level_5[p].id },
    { for p in toset(lookup(local.paths_by_depth, 6, [])) : p => aws_api_gateway_resource.path_level_6[p].id }
  )
}

# ----------------------------
# Authorizer Lambda (per API)
# ZIP is part of the module
# ----------------------------

resource "aws_lambda_function" "jwt_authorizer" {
  function_name = "${var.name}-entra-jwt-authorizer"
  role          = aws_iam_role.authorizer_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 10

  filename         = "${path.module}/authorizer.zip"
  source_code_hash = filebase64sha256("${path.module}/authorizer.zip")

  environment {
    variables = {
      JWT_ISSUER   = local.jwt_issuer
      JWT_AUDIENCE = join(",", var.jwt_audience)
    }
  }
}

resource "aws_api_gateway_authorizer" "jwt" {
  name        = "${var.name}-entra-jwt"
  rest_api_id = aws_api_gateway_rest_api.this.id

  type            = "TOKEN"
  identity_source = "method.request.header.Authorization"

  authorizer_uri                   = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${aws_lambda_function.jwt_authorizer.arn}/invocations"
  authorizer_result_ttl_in_seconds = 300
}

# ----------------------------
# Methods & Integrations
# ----------------------------

resource "aws_api_gateway_method" "this" {
  for_each = local.routes_by_key

  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = local.resource_id_by_path[each.value.path]
  http_method = each.value.method

  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.jwt.id
}

resource "aws_api_gateway_integration" "this" {
  for_each = local.routes_by_key

  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = local.resource_id_by_path[each.value.path]
  http_method = aws_api_gateway_method.this[each.key].http_method

  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${each.value.lambda_arn}/invocations"
}

# ----------------------------
# Deployments & Stage
# ----------------------------

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeploy = sha1(jsonencode({
      routes    = var.routes
      audience  = var.jwt_audience
      issuer    = local.jwt_issuer
      is_prod   = var.is_production
      whitelist = local.selected_whitelist
    }))
  }

  depends_on = [
    aws_api_gateway_integration.this,
    aws_api_gateway_method.this,
    aws_api_gateway_authorizer.jwt,
  ]
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.stage_name
}

# ----------------------------
# Custom Domain + mTLS
#
# count = 0 when domain_name is null (the default).
# Nothing below is created until you pass domain_name,
# regional_certificate_arn, and mtls_truststore_uri
# into the module call.
# ----------------------------

resource "aws_api_gateway_domain_name" "this" {
  count       = var.domain_name != null ? 1 : 0
  domain_name = var.domain_name

  regional_certificate_arn = var.regional_certificate_arn

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  # mTLS: requires the truststore_uri to be set.
  # When mtls_truststore_uri is null the block is still present but AWS
  # requires a value — so we guard the whole domain resource on domain_name
  # being set, and expect the caller to also supply mtls_truststore_uri
  # at that point.
  mutual_tls_authentication {
    truststore_uri = var.mtls_truststore_uri
  }
}

resource "aws_api_gateway_base_path_mapping" "this" {
  count       = var.domain_name != null ? 1 : 0
  api_id      = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  domain_name = aws_api_gateway_domain_name.this[0].domain_name
  base_path   = ""
}
