# ⚠️ 이 스택의 변수는 **전부 기본값을 갖는다** (계정 ID 하나만 빼고).
#
# `database` 스택이 tfvars 없이 `-var` 로 적용돼, 지금 도는 오디오 DB 의
# 설정이 리포 어디에도 없다 — `.gitignore` 가 `*.tfvars` 를 막고 있어서
# 값을 커밋할 수도 없다. 그래서 여기서는 안전한 값을 기본값으로 박아,
# `terraform apply -var aws_account_id=...` 만으로 같은 결과가 나오게 한다.
#
# 계정 ID 만 기본값을 안 준다. provider 의 `allowed_account_ids` 가드라
# 실수로 다른 계정에 적용하는 것을 막는 역할이고, 기본값을 주면 그 가드가
# 의미를 잃는다.

variable "aws_account_id" {
  description = "AWS account ID allowed for this stack"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "owner" {
  description = "Owning team tag in lowercase kebab-case"
  type        = string
  default     = "team-platform"
}

variable "data_class" {
  description = "Data classification tag in lowercase kebab-case"
  type        = string
  default     = "identity-credential"
}

variable "postgres_engine_version" {
  description = "RDS PostgreSQL engine version"
  type        = string
  default     = "18.3"
}

variable "db_instance_class" {
  description = "RDS DB instance class"
  type        = string
  default     = "db.t4g.micro"
}

# gp3 의 RDS 최소 할당량이 20 GiB 다. Keycloak 이 실제로 쓰는 양은
# 팀 규모에서 1 GiB 를 넘지 않지만 이보다 작게 잡을 수 없다.
variable "allocated_storage" {
  description = "Allocated gp3 storage in GiB"
  type        = number
  default     = 20
}

variable "database_name" {
  description = "Initial PostgreSQL database name"
  type        = string
  default     = "keycloak"
}

# 이 인스턴스에는 Keycloak 데이터만 산다. 그래서 마스터 유저로 붙어도
# 권한 범위가 앱의 데이터 범위와 같다 — 공용 인스턴스였다면 과권한이다.
# 이것이 인스턴스를 따로 세운 이유 중 하나다
# → decisions/20260807_keycloak-database-placement.md
variable "master_username" {
  description = "PostgreSQL master username; the password is managed by RDS in Secrets Manager"
  type        = string
  default     = "cntlpadmin"
}

# ⚠️ **1 은 계정 플랜이 강제하는 상한이다. 늘리지 마라.**
#
# 이 계정은 새 AWS Free Tier 의 `FREE` 플랜이고(2026-08-07 확인, 크레딧
# $109.08 / 만료 2027-01-22), 그 플랜은 백업 보관 기간을 제한한다. 7 로 두면
# apply 가 이렇게 죽는다.
#
#   FreeTierRestrictionError: The specified backup retention period exceeds
#   the maximum available to free tier customers.
#
# 오디오 DB(`cntlp-aws-api-db`)가 1일인 것도 같은 이유다 — 부주의가 아니라
# 강제였다. 유료 플랜으로 올리기 전에는 못 늘린다.
#
# Keycloak DB 는 realm·클라이언트·그룹·사용자가 전부 사는 곳이라 1일은
# 얇다. **부족한 만큼은 자동 백업이 아니라 다른 층에서 메운다.**
#
#   1일 이내      PITR (자동)
#   그 이상       수동 스냅샷 — 보관 기간 제한을 받지 않는다
#   설정 전체     realm JSON in git
#
# → decisions/20260807_keycloak-database-placement.md
variable "backup_retention_period" {
  description = "Automated backup retention period in days (capped at 1 by the FREE account plan)"
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Whether RDS deletion protection is enabled"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot when deleting the DB instance"
  type        = bool
  default     = false
}

variable "final_snapshot_identifier" {
  description = "Identifier used for the final snapshot when skip_final_snapshot is false"
  type        = string
  default     = "cntlp-aws-identity-db-final"
}
