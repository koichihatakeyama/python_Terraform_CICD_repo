# 共通モジュール置き場

ここには Lambda や CodePipeline など複数環境で再利用したい Terraform モジュールを配置する予定。

- まだモジュール化は着手前（dev 環境は `infra/dev` で単体管理）。
- stg / prod を増やすタイミングで、S3 バケットや CodePipeline を共通化するモジュールを切り出す想定。
- モジュール公開後は README に使用例や入力変数の一覧を追記すること。
