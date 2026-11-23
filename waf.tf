resource "aws_wafv2_regex_pattern_set" "http_tools" {
  name  = "${var.project}-http-tools"
  scope = "REGIONAL"

  regular_expression {
    regex_string = "(?i)^(curl|insomnia|postmanruntime|httpie|wget|python-requests|go-http-client|okhttp)"
  }
}

resource "aws_wafv2_web_acl" "protected" {
  name  = "${var.project}-protected"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # 1) Rate limit por IP
  rule {
    name     = "rate-limit-per-ip"
    priority = 0
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit                 = var.waf_rate_limit
        evaluation_window_sec = 300
        aggregate_key_type    = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  # 2) Bloqueia User-Agents de clientes HTTP conhecidos (sinal; é falsificável)
  rule {
    name     = "block-http-tool-user-agents"
    priority = 1
    action {
      block {}
    }
    statement {
      regex_pattern_set_reference_statement {
        arn = aws_wafv2_regex_pattern_set.http_tools.arn
        field_to_match {
          single_header {
            name = "user-agent"
          }
        }
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "block-http-tool-user-agents"
      sampled_requests_enabled   = true
    }
  }

  # 3) Bloqueia na borda requisições sem assinatura SigV4
  rule {
    name     = "require-sigv4-header"
    priority = 2
    action {
      block {}
    }
    statement {
      not_statement {
        statement {
          byte_match_statement {
            search_string         = "AWS4-HMAC-SHA256"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              single_header {
                name = "authorization"
              }
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "require-sigv4-header"
      sampled_requests_enabled   = true
    }
  }

  # 4) Regras gerenciadas AWS
  rule {
    name     = "aws-common-rule-set"
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-known-bad-inputs"
    priority = 4
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project}-protected"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "protected" {
  resource_arn = aws_api_gateway_stage.protected.arn
  web_acl_arn  = aws_wafv2_web_acl.protected.arn
}

resource "aws_wafv2_web_acl_logging_configuration" "protected" {
  resource_arn            = aws_wafv2_web_acl.protected.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
}
