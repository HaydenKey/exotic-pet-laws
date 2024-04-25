import json
import boto3

dynamodb = boto3.resource('dynamodb')
table_name = 'exotic_animals_legality_table'


def lambda_handler(event, context):
    # Extract state name from the request
    state_name = event['queryStringParameters']['state']

    # Query DynamoDB for the state data
    table = dynamodb.Table(table_name)
    response = table.get_item(
        Key={
            'state': state_name
        }
    )

    # Check if the item exists
    if 'Item' in response:
        state_data = response['Item']
        return {
            'statusCode': 200,
            'body': json.dumps(state_data)
        }
    else:
        return {
            'statusCode': 404,
            'body': 'State not found'
        }
