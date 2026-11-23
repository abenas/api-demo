data "archive_file" "sum" {
  type        = "zip"
  source_dir  = "${path.module}/src/sum"
  output_path = "${path.module}/build/sum.zip"
}

data "archive_file" "caller" {
  type        = "zip"
  source_dir  = "${path.module}/src/caller"
  output_path = "${path.module}/build/caller.zip"
}

resource "aws_cloudwatch_log_group" "sum" {
  name              = "/aws/lambda/${var.project}-sum"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "caller" {
  name              = "/aws/lambda/${var.project}-caller"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "sum" {
  function_name    = "${var.project}-sum"
  role             = aws_iam_role.sum.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.sum.output_path
  source_code_hash = data.archive_file.sum.output_base64sha256
  memory_size      = 256
  timeout          = 5

  depends_on = [aws_cloudwatch_log_group.sum, aws_iam_role_policy_attachment.sum_logs]
}

resource "aws_lambda_function" "caller" {
  function_name    = "${var.project}-caller"
  role             = aws_iam_role.caller.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.caller.output_path
  source_code_hash = data.archive_file.caller.output_base64sha256
  memory_size      = 256
  timeout          = 120

  environment {
    variables = {
      PROTECTED_URL = "${aws_api_gateway_stage.protected.invoke_url}/sum"
    }
  }

  depends_on = [aws_cloudwatch_log_group.caller, aws_iam_role_policy_attachment.caller_logs]
}

resource "aws_lambda_permission" "protected" {
  statement_id  = "AllowProtectedApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sum.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.protected.execution_arn}/*/POST/sum"
}

resource "aws_lambda_permission" "open" {
  statement_id  = "AllowOpenApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sum.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.open.execution_arn}/*/POST/sum"
}
