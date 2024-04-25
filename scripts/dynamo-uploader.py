import os

import boto3
import json
import os
from dotenv import load_dotenv

# Load environment variables from the .env file
load_dotenv()

# Initialize a session using the default AWS credentials
session = boto3.Session()

# Get the DynamoDB resource
dynamodb = session.resource('dynamodb')

# Define the table name
table_name = "exotic_animals_legality_table"

# Check if the DynamoDB table exists, if not, make it
try:
    table = dynamodb.Table(table_name)
    response = table.table_status
    print("Table exists!")
except dynamodb.meta.client.exceptions.ResourceNotFoundException:
    table = dynamodb.create_table(
        TableName=table_name,
        KeySchema=[
            {
                'AttributeName': 'state',
                'KeyType': 'HASH'  # Partition key
            }
        ],
        AttributeDefinitions=[
            {
                'AttributeName': 'state',
                'AttributeType': 'S'  # String
            }
        ],
        ProvisionedThroughput={
            'ReadCapacityUnits': 5,
            'WriteCapacityUnits': 5
        }
    )

    # Wait until the table exists
    table.wait_until_exists()

    print(f"Table '{table_name}' created successfully.")

# # Read data from the JSON file
# with open("../data/exotic_animals_legality_data.json", "r") as file:
#     data = json.load(file)
#
# # Insert data into the table
# for item in data:
#     table.put_item(Item=item)
#
# print("Data inserted into the table successfully. " + str(table.item_count) + " entries created.")
