locals {
  availability_zones = slice(
    data.aws_availability_zones.available.names,
    0,
    2,
  )

  public_subnets = {
    for index, cidr in var.public_subnet_cidrs :
    tostring(index) => {
      cidr = cidr
      az   = local.availability_zones[index]
    }
  }

  control_plane_name = "aws-control-plane"
  worker_names = [
    for index in range(var.worker_count) :
    format("aws-worker-%d", index + 1)
  ]

  # AWS tags are used for cloud governance and Ansible inventory discovery.
  # Kubernetes Node labels are applied later by Ansible.
  default_tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
    Area      = "aws"
  }
}
