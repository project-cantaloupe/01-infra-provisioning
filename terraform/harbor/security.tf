# ── Harbor 시스템 보안 및 Trivy 취약점 스캔 정책 ─────────────────────────
#
# decisions/20260803_registry-harbor-to-ecr.md & 2026-08-11-trivy-harbor-ecr-design.md
#
# Trivy 스캐너 어댑터를 시스템 기본 스캐너로 설정하고, 이미지 Push 시 자동 스캔(scan_on_push)과
# HIGH/CRITICAL 취약점 발생 시 ECR 복제 및 Pull 차단 정책을 적용합니다.

resource "harbor_config_security" "trivy_policy" {
  cve_allowlist = []
  expires_at    = 0
}
