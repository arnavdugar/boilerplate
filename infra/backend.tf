terraform {
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "your-app/production"
  }
}
