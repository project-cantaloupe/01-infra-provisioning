resource "harbor_project" "library" {
  name                   = "library"
  public                 = true
  vulnerability_scanning = true
  deployment_security    = "high"
  vulnerability_scanner  = "Trivy"
}
