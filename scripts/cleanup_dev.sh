#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_ROOT}/infra/dev"
AWS_VAULT_PROFILE="${AWS_VAULT_PROFILE:-terraform-operator}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
BACKEND_BUCKET="${BACKEND_BUCKET:-python-terraform-cicd-tfstate-dev}"
BACKEND_DYNAMODB_TABLE="${BACKEND_DYNAMODB_TABLE:-python-terraform-cicd-tf-lock-dev}"
BACKEND_REGION="${BACKEND_REGION:-${AWS_REGION}}"

if ! command -v aws-vault >/dev/null 2>&1; then
  echo "[ERROR] aws-vault が見つかりません。インストールしてください。" >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "[ERROR] aws CLI が見つかりません。インストールしてください。" >&2
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "[ERROR] Terraform がインストールされていません。" >&2
  exit 1
fi

aws_vault_exec() {
  aws-vault exec "${AWS_VAULT_PROFILE}" --no-session -- "$@"
}

cd "${TF_DIR}"

echo "[INFO] terraform init を確認中..."
aws_vault_exec terraform init -input=false >/dev/null

if ! ARTIFACT_BUCKET=$(aws_vault_exec terraform output -raw artifact_bucket_name 2>/dev/null); then
  echo "[ERROR] artifact_bucket_name の取得に失敗しました。先に terraform apply を実行し、state を作成してください。" >&2
  exit 1
fi

if [ -z "${ARTIFACT_BUCKET}" ]; then
  echo "[ERROR] artifact_bucket_name が空です。" >&2
  exit 1
fi

echo "[INFO] アーティファクトバケット (${ARTIFACT_BUCKET}) を削除対象に設定"

if aws_vault_exec aws s3api head-bucket --bucket "${ARTIFACT_BUCKET}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "[INFO] バケット内のオブジェクトを削除中..."
  aws_vault_exec aws s3 rm "s3://${ARTIFACT_BUCKET}" --recursive --region "${AWS_REGION}" --only-show-errors || true
else
  echo "[WARN] バケット ${ARTIFACT_BUCKET} が見つかりませんでした。既に削除済みかアクセス権がない可能性があります。"
fi

echo "[INFO] terraform destroy を実行します..."
if ! aws_vault_exec terraform destroy -auto-approve; then
  echo "[ERROR] terraform destroy に失敗しました。残リソースを確認してください。" >&2
  exit 1
fi

if aws_vault_exec aws s3api head-bucket --bucket "${BACKEND_BUCKET}" --region "${BACKEND_REGION}" >/dev/null 2>&1; then
  echo "[INFO] backend バケット (${BACKEND_BUCKET}) の中身を削除します..."
  aws_vault_exec aws s3 rm "s3://${BACKEND_BUCKET}" --recursive --region "${BACKEND_REGION}" --only-show-errors || true
  echo "[INFO] backend バケット (${BACKEND_BUCKET}) を削除します..."
  aws_vault_exec aws s3api delete-bucket --bucket "${BACKEND_BUCKET}" --region "${BACKEND_REGION}" || true
else
  echo "[WARN] backend バケット ${BACKEND_BUCKET} が見つかりませんでした。"
fi

if aws_vault_exec aws dynamodb describe-table --table-name "${BACKEND_DYNAMODB_TABLE}" --region "${BACKEND_REGION}" >/dev/null 2>&1; then
  echo "[INFO] DynamoDB ロックテーブル (${BACKEND_DYNAMODB_TABLE}) を削除します..."
  aws_vault_exec aws dynamodb delete-table --table-name "${BACKEND_DYNAMODB_TABLE}" --region "${BACKEND_REGION}" >/dev/null
  aws_vault_exec aws dynamodb wait table-not-exists --table-name "${BACKEND_DYNAMODB_TABLE}" --region "${BACKEND_REGION}" >/dev/null
else
  echo "[WARN] DynamoDB テーブル ${BACKEND_DYNAMODB_TABLE} が見つかりませんでした。"
fi

rm -rf .terraform terraform.tfstate* >/dev/null 2>&1 || true

echo "[INFO] クリーンアップが完了しました（アーティファクト S3、Terraform backend、DynamoDB を含む全削除）。"
