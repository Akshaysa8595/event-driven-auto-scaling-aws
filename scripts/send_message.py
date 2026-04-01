"""
import boto3

queue_url = "https://sqs.ap-south-1.amazonaws.com/493736153073/event-driven-queue"

sqs = boto3.client('sqs')

response = sqs.send_message(
    QueueUrl=queue_url,
    MessageBody="Hello Akshay "
)

print("Sent:", response['MessageId'])
"""
import boto3
import time
import random

sqs = boto3.client('sqs')
queue_url = "https://sqs.ap-south-1.amazonaws.com/493736153073/event-driven-queue"

while True:
    response = sqs.receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=1,
        WaitTimeSeconds=10
    )

    messages = response.get('Messages', [])

    for message in messages:
        try:
            body = message['Body']
            print("Processing:", body)

            # 🔥 Simulate random failure
            if random.choice([True, False]):
                raise Exception("Simulated failure")

            print("Processed successfully:", body)

            sqs.delete_message(
                QueueUrl=queue_url,
                ReceiptHandle=message['ReceiptHandle']
            )

        except Exception as e:
            print("Error:", str(e))
            #  Do NOT delete message → it will retry

    time.sleep(2)