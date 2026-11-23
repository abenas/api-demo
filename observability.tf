locals {
  access_log_format = jsonencode({
    requestId          = "$context.requestId"
    ip                 = "$context.identity.sourceIp"
    userAgent          = "$context.identity.userAgent"
    caller             = "$context.identity.userArn"
    method             = "$context.httpMethod"
    path               = "$context.resourcePath"
    status             = "$context.status"
    errorMessage       = "$context.error.message"
    responseLatency    = "$context.responseLatency"
    integrationLatency = "$context.integrationLatency"
    wafStatus          = "$context.waf.status"
    wafLatency         = "$context.waf.latency"
    authorizeLatency   = "$context.authorize.latency"
  })
}

resource "aws_cloudwatch_log_group" "protected_access" {
  name              = "/aws/apigateway/${var.project}-protected"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "open_access" {
  name              = "/aws/apigateway/${var.project}-open"
  retention_in_days = var.log_retention_days
}

# Logs do WAF: o nome do log group precisa começar com "aws-waf-logs-".
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${var.project}"
  retention_in_days = var.log_retention_days
}
