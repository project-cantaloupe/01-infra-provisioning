output "worker_node_01_internal_ip" {
  description = "Internal IP of cntlp-gcp-wk-01"
  value       = google_compute_instance.worker_node_01.network_interface[0].network_ip
}

output "worker_node_02_internal_ip" {
  description = "Internal IP of cntlp-gcp-wk-02"
  value       = google_compute_instance.worker_node_02.network_interface[0].network_ip
}

output "metrics_disk_id" {
  description = "Resource ID of the persistent disk for Kubernetes PV manifest"
  value       = google_compute_disk.metrics_disk.id
}