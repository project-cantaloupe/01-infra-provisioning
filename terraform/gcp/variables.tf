variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "region" {
  type        = string
  default     = "asia-northeast3"
  description = "GCP Region (Seoul)"
}

variable "zone" {
  type        = string
  default     = "asia-northeast3-a"
  description = "GCP Zone"
}
