#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_ROOT}/infra/dev"
AWS_VAULT_PROFILE="${AWS_VAULT_PROFILE:-terraform-operator}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

if ! command -v aws-vault >/dev/null 2>&1; then
  echo "[ERROR] aws-vault が見つかりません。インストールしてください。" >&2
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
aws_vault_exec terraform destroy -auto-approve

echo "[INFO] クリーンアップが完了しました。"
