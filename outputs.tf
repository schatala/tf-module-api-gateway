output "rest_api_id" {
  value       = aws_api_gateway_rest_api.this.id
  description = "REST API id."
}

output "invoke_url" {
  value       = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.this.stage_name}"
  description = "Base invoke URL."
}

output "authorizer_lambda_arn" {
  value       = aws_lambda_function.jwt_authorizer.arn
  description = "ARN of the created Entra JWT authorizer Lambda (per API)."
}

# Only populated once domain_name is set and the custom domain is created.
output "custom_domain_target" {
  value       = var.domain_name != null ? aws_api_gateway_domain_name.this[0].regional_domain_name : null
  description = "Point your DNS CNAME to this value when the custom domain is active."
}
