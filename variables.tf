variable "aws_profile" {
  type    = string
  default = "dev"
}

variable "aws_region" {
  type    = string
  default = "sa-east-1"
}

variable "project" {
  description = "Prefixo dos recursos. As roles IAM precisam começar com api-demo- (escopo da inline policy)."
  type        = string
  default     = "api-demo"
}

variable "allowed_cidrs" {
  description = "CIDRs autorizados a chamar o endpoint aberto (sua máquina local)."
  type        = list(string)
}

variable "waf_rate_limit" {
  description = "Máximo de requisições por IP a cada 5 minutos no endpoint protegido."
  type        = number
  default     = 500
}

variable "log_retention_days" {
  type    = number
  default = 3
}
