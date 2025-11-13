# CodeBuildとS3で使う共通名をまとめる
locals {
  name_prefix       = "${var.project_name}-${var.environment}"
  codebuild_name    = "${var.project_name}-${var.environment}-build"
  codedeploy_app    = "${var.project_name}-${var.environment}-codedeploy"
  codedeploy_dg     = "${var.project_name}-${var.environment}-deployment"
  lambda_name       = "${var.project_name}-${var.environment}-lambda"
  lambda_alias_name = "live"
  pipeline_name     = "${var.project_name}-${var.environment}-pipeline"
  pipeline_role_name = var.pipeline_service_role_name != "" ? var.pipeline_service_role_name : "${var.project_name}-${var.environment}-pipeline-role"
}

# CodePipeline成果物用のS3バケット
resource "aws_s3_bucket" "artifact" {
  bucket        = "${var.artifact_bucket_base}-${var.environment}"
  force_destroy = true

  tags = {
    Name        = "${var.artifact_bucket_base}-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# バージョニングでロールバックを容易にする
resource "aws_s3_bucket_versioning" "artifact" {
  bucket = aws_s3_bucket.artifact.id

  versioning_configuration {
    status = "Enabled"
  }
}

# バケット内データを常時暗号化する
resource "aws_s3_bucket_server_side_encryption_configuration" "artifact" {
  bucket = aws_s3_bucket.artifact.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# バケットの公開を禁止する設定
resource "aws_s3_bucket_public_access_block" "artifact" {
  bucket = aws_s3_bucket.artifact.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CodeBuildのログ保存先
resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${local.name_prefix}"
  retention_in_days = 14

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# CodeBuild用サービスロール
resource "aws_iam_role" "codebuild" {
  name = "${local.name_prefix}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# CloudWatch Logs書き込みとS3成果物の読み書き権限
resource "aws_iam_role_policy" "codebuild" {
  name = "${local.name_prefix}-codebuild-policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_group.codebuild.arn,
          "${aws_cloudwatch_log_group.codebuild.arn}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.artifact.arn,
          "${aws_s3_bucket.artifact.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:GetAlias",
          "lambda:PublishVersion",
          "lambda:UpdateFunctionCode"
        ]
        Resource = [
          aws_lambda_function.app.arn,
          aws_lambda_alias.active.arn
        ]
      }
    ]
  })
}

# Lambda成果物を作るCodeBuild定義
resource "aws_codebuild_project" "lambda_package" {
  name          = local.codebuild_name
  description   = "${var.project_name} ${var.environment} Lambda build"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  environment {
    type            = "LINUX_CONTAINER"
    image           = "aws/codebuild/standard:7.0"
    compute_type    = "BUILD_GENERAL1_SMALL"
    privileged_mode = false
    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
    environment_variable {
      name  = "LAMBDA_FUNCTION_NAME"
      value = local.lambda_name
    }
    environment_variable {
      name  = "LAMBDA_ALIAS_NAME"
      value = local.lambda_alias_name
    }
  }

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = aws_cloudwatch_log_group.codebuild.name
    }
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Lambda用サービスロール
resource "aws_iam_role" "lambda" {
  name = "${local.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# CloudWatch Logs出力用にAWS管理ポリシーを付与
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ローカルのLambdaコードをZIP化
data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_src"
  output_path = "${path.module}/build/lambda.zip"
}

# Terraformが管理するLambda本体
resource "aws_lambda_function" "app" {
  function_name    = local.lambda_name
  role             = aws_iam_role.lambda.arn
  runtime          = var.lambda_runtime
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  publish          = true

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# CodeDeployで制御するエイリアス
resource "aws_lambda_alias" "active" {
  name             = local.lambda_alias_name
  description      = "Active alias managed by CodeDeploy"
  function_name    = aws_lambda_function.app.function_name
  function_version = aws_lambda_function.app.version
}

# CodeDeploy用サービスロール
resource "aws_iam_role" "codedeploy" {
  name = "${local.name_prefix}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# CodeDeployにAWS管理ポリシーを付ける
resource "aws_iam_role_policy_attachment" "codedeploy_managed" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForLambda"
}

# Lambda用CodeDeployアプリ
resource "aws_codedeploy_app" "lambda" {
  name             = local.codedeploy_app
  compute_platform = "Lambda"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Lambda用デプロイメントグループ
resource "aws_codedeploy_deployment_group" "lambda" {
  app_name               = aws_codedeploy_app.lambda.name
  deployment_group_name  = local.codedeploy_dg
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = "CodeDeployDefault.LambdaAllAtOnce"

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# CodePipeline用サービスロール
resource "aws_iam_role" "codepipeline" {
  name = local.pipeline_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# CodePipelineのアクセス権
resource "aws_iam_role_policy" "codepipeline" {
  name = "${local.name_prefix}-pipeline-policy"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload"
        ]
        Resource = [
          aws_s3_bucket.artifact.arn,
          "${aws_s3_bucket.artifact.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.artifact.arn
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = aws_codebuild_project.lambda_package.arn
      },
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:GetDeploymentGroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "codestar-connections:UseConnection"
        Resource = var.codestar_connection_arn
      },
      {
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = aws_iam_role.codebuild.arn
      }
    ]
  })
}

# CodePipeline本体
resource "aws_codepipeline" "lambda" {
  name     = local.pipeline_name
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifact.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]
      configuration = {
        ConnectionArn        = var.codestar_connection_arn
        FullRepositoryId     = var.github_full_repository_id
        BranchName           = var.github_branch
          OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]
      configuration = {
        ProjectName = aws_codebuild_project.lambda_package.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      version         = "1"
      input_artifacts = ["BuildOutput"]
      configuration = {
        ApplicationName     = aws_codedeploy_app.lambda.name
        DeploymentGroupName = aws_codedeploy_deployment_group.lambda.deployment_group_name
      }
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
