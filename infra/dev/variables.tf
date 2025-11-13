# 開発環境で使う入力変数をまとめたファイル
variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "プロジェクト名"
  type        = string
  default     = "python-terraform-cicd"
}

variable "environment" {
  description = "デプロイ環境名"
  type        = string
  default     = "dev"
}

variable "artifact_bucket_base" {
  description = "CodePipelineアーティファクトバケットのベース名"
  type        = string
  default     = "python-terraform-cicd-artifact"
}

variable "lambda_runtime" {
  description = "Lambdaのランタイム"
  type        = string
  default     = "python3.11"
}

variable "lambda_timeout" {
  description = "Lambdaのタイムアウト秒"
  type        = number
  default     = 10
}

variable "lambda_memory_size" {
  description = "Lambdaのメモリ(MB)"
  type        = number
  default     = 128
}
