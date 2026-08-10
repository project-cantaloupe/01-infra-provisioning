# ── confidential 클라이언트의 시크릿을 배달하는 경로 ───────────────
#
# ArgoCD 는 public + PKCE 라 배달할 것이 없었다. **Grafana 부터는 다르다** —
# Grafana 의 `auth.generic_oauth` 는 `client_secret` 을 필수로 요구하고
# (13.1 공식 문서 확인), `use_pkce` 를 켜도 면제되지 않는다. 서버 사이드에서
# 코드를 교환하는 구조라서다.
#
# 그래서 진짜 자격증명이 하나 생기고, 그것을 클러스터로 옮겨야 한다.
# **이미 있는 경로를 따른다** — Secrets Manager → ESO → k8s Secret.
# Keycloak 자신이 DB 비밀번호를 받는 경로와 같다.
#
#   왜 Vault 가 아닌가: ESO 가 Vault 를 읽으려면 Vault 의 Kubernetes auth
#   method 가 서 있어야 하는데 아직 없다. 그리고 Vault 사람 로그인을
#   Keycloak 으로 옮기는 것이 이 태스크라, Keycloak 클라이언트를 세우는 데
#   Vault 를 끌어들이면 사슬이 하나 더 는다
#   → platform/aws/secops/keycloak/manifests/external-secret.yaml 의 같은 논지
#
# ── ⚠️ 시크릿은 tfstate 에 남는다. 그게 받아들일 만한 이유 ──────
#
# terraform keycloak provider 는 클라이언트의 모든 속성을 state 에 넣는다.
# `client_secret` 도 예외가 아니고, 이건 우회할 수 없다.
#
# 받아들이는 근거는 **tfstate 가 이미 그 등급으로 보호되고 있어서**다 —
# `cntlp-aws-tfstate` 버킷 + 전용 KMS 키. `CONSTRAINTS.md` 가 각 backend 에
# `kms_key_id` 를 요구하는 이유가 정확히 이것이다
# → decisions/20260731_tfstate-bucket-and-encryption.md
#
# **public 을 못 쓸 때만 여기로 온다.** 앱이 PKCE 만으로 되면 그쪽이 낫다.

locals {
  # 모든 OIDC 클라이언트 시크릿이 사는 접두사.
  #
  # ⚠️ **접두사를 하나로 모으는 것이 의도다.** 노드 IAM 이 이 접두사
  # 하나만 읽게 하면, 클라이언트를 붙일 때마다 IAM 을 수술하지 않아도 된다.
  # 대신 이 접두사 아래 것은 워커 노드의 **모든** 파드가 읽는다 —
  # IRSA 가 없어 권한이 노드 단위라서다
  # → decisions/20260806_cert-manager-node-instance-profile.md
  #
  # 그래서 여기에는 **OIDC 클라이언트 시크릿만** 넣는다. DB 비밀번호처럼
  # 등급이 다른 것을 섞으면 이 접두사 하나가 뚫렸을 때 범위가 넓어진다.
  oidc_secret_prefix = "cntlp/oidc"
}

resource "aws_secretsmanager_secret" "grafana_oidc" {
  name        = "${local.oidc_secret_prefix}/grafana"
  description = "Grafana generic_oauth client secret (realm cantaloupe). terraform/keycloak 이 소유한다."

  # 실수로 지웠을 때 되돌릴 창을 둔다. 기본 30일은 재생성 실험을 막으므로
  # 짧게 잡는다 — 값은 terraform 이 언제든 다시 만들 수 있다.
  recovery_window_in_days = 7

  tags = {
    Project   = "cantaloupe"
    ManagedBy = "terraform"
    Stack     = "keycloak"
  }
}

resource "aws_secretsmanager_secret_version" "grafana_oidc" {
  secret_id = aws_secretsmanager_secret.grafana_oidc.id

  # JSON 으로 넣는다. ESO 가 `property` 로 한 키씩 뽑을 수 있고, 나중에
  # 필드를 늘려도 소비자가 안 깨진다.
  secret_string = jsonencode({
    client_id     = keycloak_openid_client.grafana.client_id
    client_secret = keycloak_openid_client.grafana.client_secret
  })
}

# ── 노드가 이 접두사를 읽게 한다 ────────────────────────────────
#
# ESO 컨트롤러는 `auth:` 블록 없이 AWS SDK 기본 자격증명 체인을 타고,
# 그 끝이 IMDS 다. 즉 **워커 노드의 Instance Profile** 로 읽는다.
#
# ⚠️ **역할을 이름으로 참조한다.** `terraform/aws/compute` 의 상태를 읽지
# 않는 것은 그 스택이 EC2 인스턴스를 소유하기 때문이다 — 시크릿 하나를
# 붙이려고 노드를 재생성할 위험을 지는 교환은 성립하지 않는다.
# 인라인 정책은 이름별로 독립이라 두 스택이 같은 역할에 각자 붙여도 된다.
data "aws_iam_role" "worker_node" {
  name = var.worker_node_role_name
}

data "aws_iam_policy_document" "oidc_client_secrets" {
  statement {
    sid       = "ReadOidcClientSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:*:*:secret:${local.oidc_secret_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "oidc_client_secrets" {
  name   = "cntlp-aws-oidc-client-secrets-node"
  role   = data.aws_iam_role.worker_node.name
  policy = data.aws_iam_policy_document.oidc_client_secrets.json
}

# Harbor. 위 Grafana 와 같은 경로를 탄다 — 접두사를 공유하므로 IAM 은
# 그대로다. **접두사를 모은 값이 여기서 처음 회수된다.**
resource "aws_secretsmanager_secret" "harbor_oidc" {
  name        = "${local.oidc_secret_prefix}/harbor"
  description = "Harbor OIDC client secret (realm cantaloupe). terraform/keycloak 이 소유한다."

  recovery_window_in_days = 7

  tags = {
    Project   = "cantaloupe"
    ManagedBy = "terraform"
    Stack     = "keycloak"
  }
}

resource "aws_secretsmanager_secret_version" "harbor_oidc" {
  secret_id = aws_secretsmanager_secret.harbor_oidc.id

  secret_string = jsonencode({
    client_id     = keycloak_openid_client.harbor.client_id
    client_secret = keycloak_openid_client.harbor.client_secret
  })
}

# Vault. **접두사를 공유하지만 소비자가 다르다** — 앞의 둘은 ESO 가 노드
# IAM 으로 읽어 클러스터에 넣지만, 이건 클러스터 밖 EC2 의 terraform 이
# 사람 자격증명으로 읽는다. IAM 정책은 노드용이라 여기엔 관여하지 않는다.
resource "aws_secretsmanager_secret" "vault_oidc" {
  name        = "${local.oidc_secret_prefix}/vault"
  description = "Vault OIDC client secret (realm cantaloupe). terraform/keycloak 이 소유한다."

  recovery_window_in_days = 7

  tags = {
    Project   = "cantaloupe"
    ManagedBy = "terraform"
    Stack     = "keycloak"
  }
}

resource "aws_secretsmanager_secret_version" "vault_oidc" {
  secret_id = aws_secretsmanager_secret.vault_oidc.id

  secret_string = jsonencode({
    client_id     = keycloak_openid_client.vault.client_id
    client_secret = keycloak_openid_client.vault.client_secret
  })
}
