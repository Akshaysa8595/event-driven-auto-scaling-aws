provider "aws" {
  region = var.region
}

resource "aws_sqs_queue" "main" {
  name                       = "event-driven-queue"
  visibility_timeout_seconds = 30

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

#############IAM Role#######
resource "aws_iam_role" "ec2_role" {
  name = "ec2-sqs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}
###########Policy########
resource "aws_iam_role_policy" "sqs_policy" {
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ]
      Resource = aws_sqs_queue.main.arn
    }]
  })
}
####################instance_profile###########
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-profile"
  role = aws_iam_role.ec2_role.name
}
####################EC2 Worker###########
/*
resource "aws_instance" "worker" {
  ami           = "ami-0f58b397bc5c1f2e8"
  instance_type = "t2.micro"

  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y python3
              pip3 install boto3

              cat <<EOT > /home/ec2-user/worker.py
import boto3
import time

sqs = boto3.client('sqs')
queue_url = "${aws_sqs_queue.main.id}"

while True:
    response = sqs.receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=1,
        WaitTimeSeconds=10
    )

    messages = response.get('Messages', [])

    for message in messages:
        print("Received:", message['Body'])

        sqs.delete_message(
            QueueUrl=queue_url,
            ReceiptHandle=message['ReceiptHandle']
        )

    time.sleep(2)
              EOT

              python3 /home/ec2-user/worker.py
              EOF

  tags = {
    Name = "sqs-worker"
  }
}
*/

resource "aws_launch_template" "worker_lt" {
  name_prefix   = "worker-template-"
  image_id      = "ami-0f58b397bc5c1f2e8"
  instance_type = "t2.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = base64encode(<<-EOF
#!/bin/bash

yum update -y
yum install -y python3
pip3 install boto3

# 🔥 Install CloudWatch Logs agent
yum install -y awslogs

# 🔥 Configure logs
cat <<EOT > /etc/awslogs/awslogs.conf
[general]
state_file = /var/lib/awslogs/agent-state

[/var/log/messages]
file = /var/log/messages
log_group_name = worker-logs
log_stream_name = {instance_id}
datetime_format = %b %d %H:%M:%S
EOT

# 🔥 Start logs service
systemctl start awslogsd
systemctl enable awslogsd

# 🔥 Your worker script
cat <<EOT > /home/ec2-user/worker.py
import boto3
import time
import random

sqs = boto3.client('sqs')
queue_url = "${aws_sqs_queue.main.id}"

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

            if random.choice([True, False]):
                raise Exception("Simulated failure")

            print("Processed successfully:", body)

            sqs.delete_message(
                QueueUrl=queue_url,
                ReceiptHandle=message['ReceiptHandle']
            )

        except Exception as e:
            print("Error:", str(e))

    time.sleep(2)
EOT

python3 /home/ec2-user/worker.py
EOF
)
}

resource "aws_autoscaling_group" "worker_asg" {
  desired_capacity = 1
  max_size         = 3
  min_size         = 1

  vpc_zone_identifier = ["subnet-080b91534502e96d5"] # ⚠️ replace

  launch_template {
    id      = aws_launch_template.worker_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "sqs-worker"
    propagate_at_launch = true
  }
}

resource "aws_cloudwatch_metric_alarm" "scale_up" {
  alarm_name          = "scale-up"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = 5

  dimensions = {
    QueueName = aws_sqs_queue.main.name
  }

  alarm_description = "Scale up when queue > 5"

  alarm_actions = [aws_autoscaling_policy.scale_up_policy.arn]
}
resource "aws_autoscaling_policy" "scale_up_policy" {
  name                   = "scale-up-policy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.worker_asg.name
}
resource "aws_autoscaling_policy" "scale_down_policy" {
  name                   = "scale-down-policy"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.worker_asg.name
}
resource "aws_cloudwatch_metric_alarm" "scale_down" {
  alarm_name          = "scale-down"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Average"
  threshold           = 1

  dimensions = {
    QueueName = aws_sqs_queue.main.name
  }

  alarm_description = "Scale down when queue is empty"

  alarm_actions = [aws_autoscaling_policy.scale_down_policy.arn]
}
resource "aws_sqs_queue" "dlq" {
  name = "event-driven-dlq"
}