terraform {
  backend "gcs" {
    bucket = "webp-to-jpeg-tfstate"
  }
}

provider "google" {
  project = var.project_id
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "project_id" {
  type    = string
  default = "webp-to-jpeg"
}

variable "project_name" {
  type    = string
  default = "webp-to-jpeg"
}

variable "enable_services" {
  type    = list(string)
  default = ["artifactregistry.googleapis.com", "cloudbuild.googleapis.com", "cloudfunctions.googleapis.com", "eventarc.googleapis.com", "run.googleapis.com"]
}

resource "google_project_service" "service" {
  for_each = toset(var.enable_services)
  service  = each.key
}

resource "random_pet" "bucket_prefix" {}

module "source_bucket" {
  source   = "./one-day-storage"
  location = var.region
  name     = "source-bucket-${random_pet.bucket_prefix.id}"
}

module "destination_bucket" {
  source   = "./one-day-storage"
  location = var.region
  name     = "destination-bucket-${random_pet.bucket_prefix.id}"
}

data "archive_file" "asset" {
  output_path = "tmp/asset.zip"
  type        = "zip"
  source_dir  = "function"
}

module "asset_bucket" {
  source   = "./one-day-storage"
  location = var.region
  name     = "asset-bucket-${random_pet.bucket_prefix.id}"
}

resource "google_storage_bucket_object" "asset_object" {
  bucket = module.asset_bucket.name
  name   = data.archive_file.asset.output_md5
  source = data.archive_file.asset.output_path
}

resource "google_service_account" "runner" {
  account_id = "runner"
}

resource "google_project_iam_member" "runner" {
  member  = "serviceAccount:${google_service_account.runner.email}"
  project = var.project_id
  role    = "roles/storage.objectAdmin"
}

data "google_storage_project_service_account" "gcs_account" {
}

resource "google_project_iam_member" "gcs_pubsub" {
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
  project = var.project_id
  role    = "roles/pubsub.publisher"
}

resource "google_cloudfunctions2_function" "function" {
  name = var.project_name
  build_config {
    entry_point = "CloudEventFunc"
    runtime     = "go120"
    source {
      storage_source {
        bucket = module.asset_bucket.name
        object = google_storage_bucket_object.asset_object.name
      }
    }
  }
  event_trigger {
    event_type = "google.cloud.storage.object.v1.finalized"
    event_filters {
      attribute = "bucket"
      value     = module.source_bucket.name
    }
  }
  location = var.region
  service_config {
    environment_variables = {
      DESTINATION_BUCKET = module.destination_bucket.name
    }
  }
}

resource "google_cloudbuild_trigger" "cloudbuild" {
  filename = "cloudbuild.yaml"
  github {
    owner = "hsmtkk"
    name  = var.project_name
    push {
      branch = "main"
    }
  }
}