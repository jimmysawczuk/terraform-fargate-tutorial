provider "aws" {
  region  = "us-east-1"
  profile = "tfuser"
}

terraform {
  required_version = ">= 1.0"

  backend "s3" {
    bucket  = "terraform"
    key     = "terraform.tfstate"
    region  = "us-east-1"
    profile = "tfuser"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.42.0"
    }
  }
}
