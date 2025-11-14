# Terraform state からクリーンアップスクリプトが参照する値

output "artifact_bucket_name" {
	description = "CodePipeline が成果物を格納する S3 バケット名"
	value       = aws_s3_bucket.artifact.bucket
}

output "codepipeline_name" {
	description = "プロビジョニング済みの CodePipeline 名"
	value       = aws_codepipeline.lambda.name
}

