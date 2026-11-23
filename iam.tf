data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Executa a Lambda de soma (apenas logs).
resource "aws_iam_role" "sum" {
  name               = "${var.project}-sum-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "sum_logs" {
  role       = aws_iam_role.sum.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Origem governada: ÚNICA identidade aceita pelo endpoint protegido.
resource "aws_iam_role" "caller" {
  name               = "${var.project}-caller-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "caller_logs" {
  role       = aws_iam_role.caller.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "caller_invoke" {
  statement {
    actions   = ["execute-api:Invoke"]
    resources = ["${aws_api_gateway_rest_api.protected.execution_arn}/*/POST/sum"]
  }
}

resource "aws_iam_role_policy" "caller_invoke" {
  name   = "invoke-protected-api"
  role   = aws_iam_role.caller.id
  policy = data.aws_iam_policy_document.caller_invoke.json
}

# Role usada pelo API Gateway (configuração regional da conta) para gravar access logs.
resource "aws_iam_role" "apigw_logs" {
  name = "${var.project}-apigw-logs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "apigateway.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "apigw_logs" {
  role       = aws_iam_role.apigw_logs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigw_logs.arn
  depends_on          = [aws_iam_role_policy_attachment.apigw_logs]
}
