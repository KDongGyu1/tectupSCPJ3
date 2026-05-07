locals {
  app_services = {
    payment = { name = "payment-api", path = "/payments/*", description = "Payment API" }
    auth    = { name = "auth-user-api", path = "/auth/*", description = "Auth and user API" }
    ops     = { name = "ops-audit-api", path = "/ops/*", description = "Operations and audit API" }
  }
}
