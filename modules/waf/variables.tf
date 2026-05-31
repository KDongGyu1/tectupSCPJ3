variable "name_prefix" { type = string }
variable "alb_arn" { type = string }
variable "waf_rate_rule_action" { type = string }
variable "waf_rate_limits" {
  type = object({
    auth         = number
    payments     = number
    transactions = number
    ops          = number
    audit        = number
  })
}
