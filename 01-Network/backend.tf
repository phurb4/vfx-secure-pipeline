terraform {
  backend "s3" {
    bucket                      = "vfx-tfstate"
    key                         = "01-network/terraform.tfstate"
    region                      = "us-east-1"
    endpoints                   = { s3 = "http://localhost:4566" }
    use_path_style              = true
    use_lockfile                = true
    encrypt                     = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
  }
}