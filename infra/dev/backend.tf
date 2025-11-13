terraform {
  backend "s3" {
    bucket         = "python-terraform-cicd-tfstate-dev"
    key            = "state/dev.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "python-terraform-cicd-tf-lock-dev"
    encrypt        = true
  }
}