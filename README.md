
# Event-Driven Auto Scaling System on AWS

## Overview

This project demonstrates a production-style event-driven architecture where compute resources automatically scale based on workload using AWS services.

The system processes asynchronous tasks using Amazon SQS and dynamically scales EC2 instances based on queue depth using CloudWatch and Auto Scaling Groups.

---

## Architecture

Producer → SQS Queue → Auto Scaling Group (EC2 Workers) → Processing → Dead Letter Queue (on failure)

---

## Tech Stack

- AWS SQS (message queue)
- EC2 + Auto Scaling Group (worker nodes)
- CloudWatch (metrics, alarms, logs)
- Terraform (Infrastructure as Code)
- Python (message producer & consumer)

---

## Features

- Event-driven architecture using SQS
- Auto scaling based on queue length
- Dead Letter Queue (DLQ) for failure handling
- Retry mechanism using visibility timeout
- IAM role-based secure access (no hardcoded credentials)
- CloudWatch logging for observability
- Fully automated infrastructure using Terraform

---

## Scaling Logic

- Scale up when queue messages > 5
- Scale down when queue is empty
- Minimum instances: 1
- Maximum instances: 3

---

## How to Test

### 1. Deploy infrastructure

```bash
cd terraform
terraform init
terraform apply
```

### 2. Send a message

cd scripts
python send_message.py

### 3.Send burst traffic

for i in {1..20}; do python send_message.py; done
