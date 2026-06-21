# Terraform block specifies the required version of Terraform and the providers used in this configuration. 
# It ensures that the correct versions of the providers are installed and used, which helps maintain compatibility and stability.
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# The provider block configures the AWS provider with the specified region.
provider "aws" {
  region = var.aws_region
}
