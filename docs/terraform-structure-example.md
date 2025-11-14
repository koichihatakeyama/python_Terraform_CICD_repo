# Terraformのディレクトリ構成メモ

## モジュールってなに？

- Terraformの`.tf`ファイルがまとまっているフォルダが1つの“モジュール”である。
- `terraform init` / `plan` / `apply`はモジュール単位で実行する。
- たとえば`infra/`に置いた`.tf`一式は「このプロジェクトのインフラを定義するモジュール」である。
- モジュールは入れ子にもでき、共通化したいリソースを`modules/xxx`に切り出して再利用すると整理しやすい。

## 環境ごとの構成例

```text
infra/
├── dev/
│   ├── main.tf        # 開発環境向け設定（変数値やタグをdev用にする）
│   ├── variables.tf
│   └── backend.tf     # terraform stateのbackend設定（S3バケット名やDynamoDBテーブルをdev用に）
├── stg/
│   └── ...            # 検証環境（staging）向け
├── prod/
│   └── ...            # 本番環境向け
└── modules/
    └── lambda_app/    # 各環境から再利用する共通モジュールを格納
```

- `dev/main.tf`から`module "lambda_app"`のように呼び出し、環境ごとに変数値（VPC ID、サブネット、タグなど）を渡すのが定番である。
- 小規模構成では環境ごとに`*.tfvars`を作り、同じ`main.tf`を使い回しつつ`terraform plan -var-file dev.tfvars`とする方法も選択肢である。

## 今回のシンプル版

- まずは`infra/`直下にすべてを置くシングルモジュールで始めても問題ない。
- 後で環境を分けたくなったら`infra/dev`,`infra/prod`のようにディレクトリを切り、共通化したい部分を`modules/`に移す流れを採ればスケールしやすい。
