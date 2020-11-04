
provider "aws" {
  version = "~> 3.10"
  region  = var.AWS_REGION
  //  secret_key = "${var.AWS_ACCESS_KEY_ID}"
  //  access_key = "${var.AWS_SECRET_ACCESS_KEY}"
}
