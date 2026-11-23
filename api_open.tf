# Endpoint aberto (baseline): sem auth, sem WAF; resource policy restrita ao seu IP.
resource "aws_api_gateway_rest_api" "open" {
  name        = "${var.project}-open"
  description = "Soma sem camada de proteção (restrita por IP de origem)"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

data "aws_iam_policy_document" "open_resource_policy" {
  statement {
    sid       = "AllowFromLocalMachine"
    effect    = "Allow"
    actions   = ["execute-api:Invoke"]
    resources = ["${aws_api_gateway_rest_api.open.execution_arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "IpAddress"
      variable = "aws:SourceIp"
      values   = var.allowed_cidrs
    }
  }

  statement {
    sid       = "DenyOtherIps"
    effect    = "Deny"
    actions   = ["execute-api:Invoke"]
    resources = ["${aws_api_gateway_rest_api.open.execution_arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "NotIpAddress"
      variable = "aws:SourceIp"
      values   = var.allowed_cidrs
    }
  }
}

resource "aws_api_gateway_rest_api_policy" "open" {
  rest_api_id = aws_api_gateway_rest_api.open.id
  policy      = data.aws_iam_policy_document.open_resource_policy.json
}

resource "aws_api_gateway_resource" "open_sum" {
  rest_api_id = aws_api_gateway_rest_api.open.id
  parent_id   = aws_api_gateway_rest_api.open.root_resource_id
  path_part   = "sum"
}

resource "aws_api_gateway_method" "open_sum" {
  rest_api_id   = aws_api_gateway_rest_api.open.id
  resource_id   = aws_api_gateway_resource.open_sum.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "open_sum" {
  rest_api_id             = aws_api_gateway_rest_api.open.id
  resource_id             = aws_api_gateway_resource.open_sum.id
  http_method             = aws_api_gateway_method.open_sum.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.sum.invoke_arn
}

resource "aws_api_gateway_deployment" "open" {
  rest_api_id = aws_api_gateway_rest_api.open.id

  triggers = {
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.open_sum.id,
      aws_api_gateway_method.open_sum.id,
      aws_api_gateway_method.open_sum.authorization,
      aws_api_gateway_integration.open_sum.id,
      aws_api_gateway_integration.open_sum.uri,
      data.aws_iam_policy_document.open_resource_policy.json,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "open" {
  rest_api_id   = aws_api_gateway_rest_api.open.id
  deployment_id = aws_api_gateway_deployment.open.id
  stage_name    = "v1"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.open_access.arn
    format          = local.access_log_format
  }

  depends_on = [aws_api_gateway_account.this]
}

resource "aws_api_gateway_method_settings" "open" {
  rest_api_id = aws_api_gateway_rest_api.open.id
  stage_name  = aws_api_gateway_stage.open.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled = true
  }
}
