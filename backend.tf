terraform {
  required_version = ">= 0.12"

  backend "s3" {
    bucket  = "terraform"
    key     = "terraform.tfstate"
    region  = "us-east-1"
    profile = "tfuser"
  }
}
