variable "aws_account_id" {
  description = "AWS account ID allowed for this stack"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "owner" {
  description = "Owning team tag in lowercase kebab-case"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.owner))
    error_message = "owner must use lowercase kebab-case, for example team-platform."
  }
}

variable "kubernetes_cluster_name" {
  description = "Self-managed Kubernetes cluster name used by Karpenter discovery tags"
  type        = string
  default     = "cntlp-k8s"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.kubernetes_cluster_name))
    error_message = "kubernetes_cluster_name must use lowercase kebab-case."
  }
}

variable "enable_controller_foundation" {
  description = "Attach the scoped Karpenter controller policy to the existing Control Plane role"
  type        = bool
  default     = false
}

variable "enable_boot_test" {
  description = "Create one temporary EC2 instance to verify the Golden AMI first boot"
  type        = bool
  default     = false
}

variable "enable_bootstrap_foundation" {
  description = "Create Tailscale OAuth and rotated kubeadm Secret containers with least-privilege Worker and Control Plane IAM"
  type        = bool
  default     = false
}

variable "boot_test_join_cluster" {
  description = "Run the secret-free Tailscale and kubeadm bootstrap on the temporary Boot Test instance"
  type        = bool
  default     = false

  validation {
    condition = (
      !var.boot_test_join_cluster
      || (var.enable_boot_test && var.enable_bootstrap_foundation)
    )
    error_message = "boot_test_join_cluster requires both enable_boot_test and enable_bootstrap_foundation."
  }
}

variable "bootstrap_expires_on" {
  description = "Expiration date tag for temporary bootstrap credential Secrets in YYYY-MM-DD format"
  type        = string
  default     = ""

  validation {
    condition = (
      !var.enable_bootstrap_foundation
      || can(formatdate("YYYY-MM-DD", "${var.bootstrap_expires_on}T00:00:00Z"))
    )
    error_message = "bootstrap_expires_on must be a valid YYYY-MM-DD date when enable_bootstrap_foundation is true."
  }
}

variable "boot_test_ami_name" {
  description = "Exact Packer Golden AMI name used only when enable_boot_test is true"
  type        = string
  default     = ""

  validation {
    condition = (
      !var.enable_boot_test
      || can(regex("^cntlp-aws-cicd-k8s-worker-[0-9a-f]{7,40}$", var.boot_test_ami_name))
    )
    error_message = "boot_test_ami_name must be an approved Cantaloupe Golden AMI name when enable_boot_test is true."
  }
}

variable "boot_test_expires_on" {
  description = "Expiration date tag for the temporary Boot Test instance in YYYY-MM-DD format"
  type        = string
  default     = ""

  validation {
    condition = (
      !var.enable_boot_test
      || can(formatdate("YYYY-MM-DD", "${var.boot_test_expires_on}T00:00:00Z"))
    )
    error_message = "boot_test_expires_on must be a valid YYYY-MM-DD date when enable_boot_test is true."
  }
}
