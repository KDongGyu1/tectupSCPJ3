# IAM Role Specification

The active IAM implementation is in `modules/iam`.

## Roles

- Operations administrator role: intended for infrastructure operation tasks with MFA-oriented access assumptions.
- Security administrator role: intended for security configuration and monitoring operations.
- Auditor role: intended for read-only audit and review workflows.
- Application instance profile: attached to private EC2 application instances.

## Notes

IAM Identity Center assignments are normally managed at the AWS Organizations or account administration layer. This Terraform project focuses on IAM roles and policies that belong to the workload.
