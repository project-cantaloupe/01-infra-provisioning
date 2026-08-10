#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
stack_dir="$(cd -- "${script_dir}/.." && pwd)"
remote_script="${script_dir}/verify-boot-test-remote.sh"

aws_profile="${AWS_PROFILE:-cntlp}"
aws_region="${CNTLP_AWS_REGION:-ap-northeast-2}"
instance_id="${CNTLP_BOOT_TEST_INSTANCE_ID:-}"

if [[ -z "${instance_id}" ]]; then
  instance_id="$(terraform -chdir="${stack_dir}" output -raw boot_test_instance_id)"
fi

if [[ ! "${instance_id}" =~ ^i-[0-9a-f]+$ ]]; then
  printf 'Boot Test instance ID를 확인할 수 없습니다: %s\n' "${instance_id}" >&2
  exit 1
fi

remote_payload="$(base64 <"${remote_script}" | tr -d '\n')"
parameters="$(printf '{"commands":["printf %%s %s | base64 -d | bash"]}' "${remote_payload}")"

command_id="$({
  aws ssm send-command \
    --profile "${aws_profile}" \
    --region "${aws_region}" \
    --instance-ids "${instance_id}" \
    --document-name AWS-RunShellScript \
    --comment "Cantaloupe Golden AMI first boot verification" \
    --parameters "${parameters}" \
    --query 'Command.CommandId' \
    --output text
})"

if ! aws ssm wait command-executed \
  --profile "${aws_profile}" \
  --region "${aws_region}" \
  --command-id "${command_id}" \
  --instance-id "${instance_id}"; then
  aws ssm get-command-invocation \
    --profile "${aws_profile}" \
    --region "${aws_region}" \
    --command-id "${command_id}" \
    --instance-id "${instance_id}" \
    --query '{Status:Status,ResponseCode:ResponseCode,Stdout:StandardOutputContent,Stderr:StandardErrorContent}' \
    --output json
  exit 1
fi

aws ssm get-command-invocation \
  --profile "${aws_profile}" \
  --region "${aws_region}" \
  --command-id "${command_id}" \
  --instance-id "${instance_id}" \
  --query 'StandardOutputContent' \
  --output text
