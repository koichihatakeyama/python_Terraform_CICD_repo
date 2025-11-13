def lambda_handler(event, context):
    """シンプルな疎通確認用のLambdaハンドラー。"""
    return {
        "statusCode": 200,
        "body": "ok"
    }
