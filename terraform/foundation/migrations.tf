removed {
  from = doppler_secret.operator
  lifecycle {
    destroy = false
  }
}

moved {
  from = minio_s3_bucket.platform[0]
  to   = minio_s3_bucket.platform
}

moved {
  from = minio_s3_bucket_versioning.platform[0]
  to   = minio_s3_bucket_versioning.platform
}
