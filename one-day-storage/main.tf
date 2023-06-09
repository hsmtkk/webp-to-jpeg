resource "google_storage_bucket" "bucket" {
  force_destroy = true
  location = var.location
  name = var.name
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 1
    }
  }
}

output "name" {
  value = google_storage_bucket.bucket.name
}