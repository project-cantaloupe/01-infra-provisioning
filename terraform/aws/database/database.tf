# RDS가 배치될 수 있는 서로 다른 두 AZ의 Private Subnet을 묶는다.
resource "aws_db_subnet_group" "api" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = data.terraform_remote_state.network.outputs.database_subnet_ids

  tags = {
    Name      = "${local.name_prefix}-db-subnet-group"
    component = local.component
  }
}

# PostgreSQL은 AWS Worker Security Group을 가진 노드에서만 접근할 수 있다.
# RDS는 Public IP를 받지 않으며 인터넷에서 5432 포트를 열지 않는다.
resource "aws_security_group" "database" {
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

# 애플리케이션 데이터를 저장할 단일 PostgreSQL RDS 인스턴스다.
# 개발 단계 비용을 줄이기 위해 Single-AZ 소형 인스턴스로 시작한다.
resource "aws_db_instance" "api" {
  identifier = "${local.name_prefix}-db"

  engine         = "postgres"
  engine_version = var.postgres_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.database_name
  username = var.master_username
  # 비밀번호를 Terraform 변수나 state에 저장하지 않고 RDS가 Secrets Manager에서 관리한다.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.api.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  multi_az               = false

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
