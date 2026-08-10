resource "aws_iam_role" "vault" {
  name = "${local.name_prefix}-vault"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Name = "${local.name_prefix}-vault"
  }
}

# awskms seal이 실제로 요구하는 셋만 준다 — Encrypt, Decrypt, DescribeKey.
# kms:* 를 주면 이 인스턴스가 tfstate 암호화 키까지 만질 수 있게 된다.
resource "aws_iam_role_policy" "unseal" {
  name = "unseal"
  role = aws_iam_role.vault.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      Resource = aws_kms_key.unseal.arn
    }]
  })
}

# 스냅샷 업로드. **s3:DeleteObject를 주지 않는다.**
# 만료는 라이프사이클 규칙이 담당하고, 인스턴스가 침해됐을 때 백업을
# 지우지 못하게 한다.
resource "aws_iam_role_policy" "snapshots" {
  name = "snapshots"
  role = aws_iam_role.vault.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.snapshots.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.snapshots.arn
      },
      # 버킷 기본 암호화가 aws:kms 라서 PutObject가 KMS 호출을 동반한다.
      # 이 권한이 없으면 업로드가 AccessDenied로 죽는데, 원인이 S3가 아니라
      # KMS라는 것이 메시지에 잘 드러나지 않는다.
      {
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Encrypt",
        ]
        Resource = aws_kms_key.unseal.arn
      },
    ]
  })
}

resource "aws_iam_instance_profile" "vault" {
  name = "${local.name_prefix}-vault"
  role = aws_iam_role.vault.name

  tags = {
    Name = "${local.name_prefix}-vault"
  }
}
