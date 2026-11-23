output "open_url" {
  value = "${aws_api_gateway_stage.open.invoke_url}/sum"
}

output "protected_url" {
  value = "${aws_api_gateway_stage.protected.invoke_url}/sum"
}

output "caller_function" {
  value = aws_lambda_function.caller.function_name
}

output "region" {
  value = data.aws_region.current.region
}
