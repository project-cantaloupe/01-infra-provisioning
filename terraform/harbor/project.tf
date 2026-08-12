resource "harbor_project" "library" {
  name                   = "library"
  public                 = true
  vulnerability_scanning = true
  deployment_security    = "high"
  vulnerability_scanner  = "Trivy"
}

resource "harbor_project_webhook" "trivy_fluentbit" {
  name        = "trivy-to-fluentbit"
  address     = "http://fluent-bit-webhook.logging.svc.cluster.local:9880/harbor.webhook"
  project_id  = harbor_project.library.id
  events_types = [
    "SCANNING_COMPLETED",
    "SCANNING_FAILED"
  ]
  notify_type = "http"
  enabled     = true
}
