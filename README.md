# VFX Secure Pipeline

Infrastructure as Code for a VFX production pipeline, with security built into every layer of the workflow (DevSecOps). 
Built with Terraform on AWS, tested first against a local AWS emulator (Floci: https://floci.io/aws/) before deployment to a real account.

## What this project does

A VFX studio needs to move an asset from the moment an artist uploads it to the moment a client approves the final delivery, across six production departments: 
Modeling, Texturing, Rigging, Animation, FX, and Compositing, followed by Final Render and Client Review. 
This repository implements that entire flow as versioned infrastructure code, with identity, network, and audit controls layered on top rather than bolted on afterward.
I designed the architecture and made every decision in this repository myself, but I’m new to writing infrastructure code.
I used Claude AI to generate the Terraform code and commands, which I then ran, tested, and debugged myself against Floci before anything touched AWS.

## Architecture overview

The project is organized into nine independent Terraform blocks, applied in order:

Network sets up the VPC with one subnet per department. Storage provisions versioned, encrypted S3 buckets and DynamoDB tables for asset metadata. 
Cognito handles identity for internal staff, external clients, and read-only guests, with mandatory MFA. 
Automation orchestrates the approval workflow with Step Functions, Lambda, and SNS. SQS queues render jobs. 
Render Farm runs EC2 Spot Instances in an Auto Scaling Group driven by queue depth. 
Audit Logging wires CloudTrail into CloudWatch with custom security alarms. 
Client Review serves final deliveries through CloudFront with signed URLs. 
Governance adds AWS Config and GuardDuty.

Each tool choice is documented with the alternatives considered and the reasoning behind the decision.

## FFmpeg binaries (not included in this repository)

The Automation block (04-Automation) uses an FFmpeg Lambda layer to burn the company logo, timecode, and absolute frame number onto review videos. 
The FFmpeg binaries themselves are not tracked in this repository, because they are large compiled files (over 100 MB) that GitHub does not accept, and because they can always be re-downloaded from their public source rather than stored as code.

Before deploying the Automation block against a real AWS account, rebuild the layer locally:

1. Download a static FFmpeg build for Linux x86_64 from the BtbN FFmpeg builds project, since AWS Lambda runs on Amazon Linux.
2. Extract the archive and copy the `ffmpeg` binary into a folder structure matching `ffmpeg-layer/bin/ffmpeg`, which is the path AWS Lambda layers expect.
3. Compress that `ffmpeg-layer` folder into `ffmpeg-layer.zip`.
4. Place the resulting `ffmpeg-layer.zip` inside `04-Automation/layers/`, matching the path already referenced by the Terraform code in that block.

Once the zip file is in place, `terraform plan` and `terraform apply` in `04-Automation` will pick it up automatically.