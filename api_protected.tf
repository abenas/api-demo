# Endpoint protegido: WAF -> Resource Policy (só a role do caller) -> IAM Auth (SigV4)
resource "aws_api_gateway_rest_api" "protected" {
  name        = "${var.project}-protected"
  description = "Soma protegida: só a role ${var.project}-caller-lambda"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

data "aws_iam_policy_document" "protected_resource_policy" {
  statement {
    sid       = "AllowGovernedCaller"
    effect    = "Allow"
    actions   = ["execute-api:Invoke"]
    resources = ["${aws_api_gateway_rest_api.protected.execution_arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.caller.arn]
    }
  }

  # Deny explícito: sem ele, qualquer identidade da conta com execute-api:Invoke
  # na sua própria policy (ex.: PowerUserAccess) conseguiria chamar a API.
  statement {
    sid       = "DenyEveryoneElse"
    effect    = "Deny"
    actions   = ["execute-api:Invoke"]
    resources = ["${aws_api_gateway_rest_api.protected.execution_arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalArn"
      values   = [aws_iam_role.caller.arn]
    }
  }
}

resource "aws_api_gateway_rest_api_policy" "protected" {
  rest_api_id = aws_api_gateway_rest_api.protected.id
  policy      = data.aws_iam_policy_document.protected_resource_policy.json
}

resource "aws_api_gateway_resource" "protected_sum" {
  rest_api_id = aws_api_gateway_rest_api.protected.id
  parent_id   = aws_api_gateway_rest_api.protected.root_resource_id
  path_part   = "sum"
}

resource "aws_api_gateway_method" "protected_sum" {
  rest_api_id   = aws_api_gateway_rest_api.protected.id
  resource_id   = aws_api_gateway_resource.protected_sum.id
  http_method   = "POST"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "protected_sum" {
  rest_api_id             = aws_api_gateway_rest_api.protected.id
  resource_id             = aws_api_gateway_resource.protected_sum.id
  http_method             = aws_api_gateway_method.protected_sum.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.sum.invoke_arn
}

resource "aws_api_gateway_deployment" "protected" {
  rest_api_id = aws_api_gateway_rest_api.protected.id

  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.protected_sum.id,
      aws_api_gateway_method.protected_sum.id,
      aws_api_gateway_method.protected_sum.authorization,
      aws_api_gateway_integration.protected_sum.id,
      aws_api_gateway_integration.protected_sum.uri,
      data.aws_iam_policy_document.protected_resource_policy.json,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "protected" {
  rest_api_id   = aws_api_gateway_rest_api.protected.id
  deployment_id = aws_api_gateway_deployment.protected.id
  stage_name    = "v1"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.protected_access.arn
    format          = local.access_log_format
  }

  depends_on = [aws_api_gateway_account.this]
}

resource "aws_api_gateway_method_settings" "protected" {
  rest_api_id = aws_api_gateway_rest_api.protected.id
  stage_name  = aws_api_gateway_stage.protected.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
  }
}
