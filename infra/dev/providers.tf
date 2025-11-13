# TerraformとAWSプロバイダーのバージョンを固定
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# AWSプロバイダーを初期化
provider "aws" {
  region = var.aws_region
}
