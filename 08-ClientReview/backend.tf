terraform {
  backend "s3" {
    bucket       = "vfx-tfstate-a7k3"
    key          = "08-clientreview/terraform.tfstate"
    region       = "us-east-2"
    use_lockfile = true
    encrypt      = true
  }
}