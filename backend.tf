terraform {
  backend "s3" {
    bucket  = "terraform"
    key     = "terraform.tfstate"
    region  = "us-east-1"
    profile = "tfuser"
  }
}
