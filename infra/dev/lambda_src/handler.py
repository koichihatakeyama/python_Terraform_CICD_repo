def lambda_handler(event, context):
    """疎通確認用Lambdaハンドラー。"""
    return {
        "statusCode": 200,
        "body": "ok"
    }
