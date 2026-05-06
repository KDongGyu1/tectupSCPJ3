terraform {
  required_version = ">= 1.6.0"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile == "" ? null : var.aws_profile

  dynamic "assume_role" {
    for_each = var.assume_role_arn == "" ? [] : [var.assume_role_arn]

    content {
      role_arn     = assume_role.value
      session_name = var.assume_role_session_name
    }
  }

  default_tags {
    tags = local.common_tags
  }
}
