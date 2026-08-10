# Keycloak 전용 PostgreSQL. 오디오 앱의 `cntlp-aws-api-db` 와 **인스턴스를
# 나눈다.** 같은 인스턴스에 논리 DB 만 추가하는 쪽이 공짜였지만, 그러면
# 오디오 앱의 부하가 SSO 를 끌어내린다 — SSO 가 죽으면 Grafana·ArgoCD 로
# 들어가 원인을 볼 수도, 롤백할 수도 없다.
# → decisions/20260807_keycloak-database-placement.md

# RDS 가 배치될 수 있는 Private Subnet 을 묶는다. `database` 스택의 것과
# 같은 서브넷을 쓰지만 그룹은 따로 만든다 — 스택 간 상태를 엮지 않기 위해서다.
resource "aws_db_subnet_group" "identity" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = data.terraform_remote_state.network.outputs.database_subnet_ids

  tags = {
    Name      = "${local.name_prefix}-db-subnet-group"
    component = local.component
  }
}

# PostgreSQL 은 AWS Worker Security Group 을 가진 노드에서만 접근할 수 있다.
# RDS 는 Public IP 를 받지 않으며 인터넷에서 5432 포트를 열지 않는다.
resource "aws_security_group" "identity_database" {
  name        = "${local.name_prefix}-db-sg"
  description = "Allow PostgreSQL only from AWS Kubernetes workers"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  ingress {
    description     = "PostgreSQL from AWS Kubernetes workers"
    protocol        = "tcp"
    from_port       = local.database_port
    to_port         = local.database_port
    security_groups = [data.terraform_remote_state.network.outputs.worker_security_group_id]
  }

  tags = {
    Name      = "${local.name_prefix}-db-sg"
    component = local.component
  }
}

resource "aws_db_instance" "identity" {
  identifier = "${local.name_prefix}-db"

  engine         = "postgres"
  engine_version = var.postgres_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.database_name
  username = var.master_username
  # 비밀번호를 Terraform 변수나 state 에 저장하지 않고 RDS 가 Secrets Manager
  # 에서 관리한다. 노드 인스턴스 프로파일이 그 시크릿을 읽어 Keycloak 에
  # 넣는다 — cert-manager·EBS CSI 와 같은 IMDS 경로다.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.identity.name
  vpc_security_group_ids = [aws_security_group.identity_database.id]
  publicly_accessible    = false
  multi_az               = false
  # 노드와 같은 AZ. 근거는 locals.tf.
  availability_zone = local.database_availability_zone

  backup_retention_period  = var.backup_retention_period
  copy_tags_to_snapshot    = true
  delete_automated_backups = false

  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : var.final_snapshot_identifier

  tags = {
    Name      = "${local.name_prefix}-db"
    component = local.component
  }
}
