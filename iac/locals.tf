locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project      = var.project_name
    Environment  = var.environment
    ManagedBy    = "terraform"
    Architecture = "fintech-platform-with-regulations"
  }

  lambda_services = {
    auth = {
      handler     = "auth.handler"
      description = "Auth helper service for RBAC checks and MFA-sensitive flows."
      regulation  = "R2,R3"
    }
    kyc = {
      handler     = "kyc.handler"
      description = "KYC/CDD/EDD orchestration service."
      regulation  = "R4"
    }
    payment = {
      handler     = "payment.handler"
      description = "Payment request service with encrypted sensitive data references."
      regulation  = "R1,R3,R4"
    }
    query = {
      handler     = "query.handler"
      description = "Role-scoped transaction query service."
      regulation  = "R3"
    }
    settlement = {
      handler     = "settlement.handler"
      description = "Approval, cancellation, refund, and settlement status service."
      regulation  = "R1,R5"
    }
    audit = {
      handler     = "audit.handler"
      description = "Audit and monitoring service."
      regulation  = "R2,R4,R5"
    }
    aml = {
      handler     = "aml.handler"
      description = "AML detection and STR/CTR reporting service."
      regulation  = "R4"
    }
    notification = {
      handler     = "notification.handler"
      description = "SMS/email customer harm and incident notification service."
      regulation  = "R5"
    }
  }

  rbac_groups = {
    Customer = {
      description = "Customer role: own payment requests and own transactions only."
      precedence  = 70
    }
    Merchant = {
      description = "Merchant role: transactions for assigned merchant only."
      precedence  = 60
    }
    SettlementOperator = {
      description = "Settlement role: settlement data and status updates."
      precedence  = 50
    }
    OperationsAdmin = {
      description = "Operations role: limited transaction operations. MFA required."
      precedence  = 40
    }
    SecurityAdmin = {
      description = "Security role: IAM/security policy operations. MFA required."
      precedence  = 30
    }
    Auditor = {
      description = "Auditor role: read-only audit and policy history. MFA required."
      precedence  = 20
    }
  }
}
