# VFX Secure Pipeline

Infrastructure as Code for a VFX production pipeline, with security built into every layer of the workflow (DevSecOps).
Built with Terraform on AWS, tested first against a local AWS emulator (Floci: https://floci.io/aws/) before deployment to a real account.

## What this project does

A VFX studio needs to move an asset from the moment an artist uploads it to the moment a client approves the final delivery, across six production departments:
Modeling, Texturing, Rigging, Animation, FX, and Compositing, followed by Final Render and Client Review.
This repository implements that entire flow as versioned infrastructure code, with identity, network, and audit controls layered on top rather than bolted on afterward.
I designed the architecture and made every decision in this repository myself, but I'm new to writing infrastructure code.
I used Claude AI to generate the Terraform code and commands, which I then ran, tested, and debugged myself against Floci before anything touched AWS.

## Roadmap: nine blocks, all built and verified against Floci

✅ 01. Network — VPC, per-department subnets, VPN, NACLs, Security Groups
Each department gets its own isolated subnet, so an artist in one department can't reach another department's resources. VPN simulates remote access to the studio's internal network, and NACLs add a second defense layer on top of Security Groups.

✅ 02. Storage — S3 + DynamoDB, versioning, encryption
S3 holds the actual files (Input/Output/Dailies) with native versioning so nothing gets silently overwritten. DynamoDB keeps a human-readable record of each version: who uploaded it, when, and its approval status. Version numbers are assigned automatically by Lambda, never by hand.

✅ 03. Identity — Cognito with MFA, IAM with time and IP-based access policies
Three separate Cognito user pools (internal team, clients, guests) with mandatory MFA for staff. IAM policies restrict access by role, time of day, and source IP, with supervisors stepping up with extra MFA instead of being hard-blocked after hours.

✅ 04. Automation — Step Functions, SNS, Lambda with FFmpeg
Step Functions orchestrates the full approval journey of an asset in one visible workflow, instead of loose Lambdas calling each other. The FFmpeg Lambda burns in timecode and frame number for review, and SNS notifies supervisors when something needs attention.

✅ 05. SQS — render job queue
Approved shots headed to final render get dropped into a queue. This decouples the approval workflow from the render farm, so render capacity scales independently of how many artists are working.

✅ 06. Render Farm — EC2 Spot Instances, Auto Scaling Group
EC2 Spot Instances handle the heavy, sustained compute that rendering needs, something Lambda isn't built for. The Auto Scaling Group watches the queue and spins instances up or down automatically, so there's zero cost sitting idle.

✅ 07. Audit Logging — CloudTrail, CloudWatch alarms
CloudTrail logs every action taken in the account, and CloudWatch watches those logs for specific patterns. Three alarms catch unusual downloads, off-hours activity, and access attempts from unrecognized IPs.

✅ 08. Client Review — CloudFront signed URLs, guest access
Clients see final deliveries through short-lived signed URLs, with no need for their own AWS account or direct bucket access. A separate read-only guest role lets recruiters or interviewers view the environment safely, with one-time email login.

✅ 09. Governance — AWS Config, GuardDuty
AWS Config checks the infrastructure against rules like "no public buckets allowed," and GuardDuty watches for threats. Budgets and resource tagging keep spending visible and broken down by department.

All nine blocks are applied against Floci, including the full replication of this pattern across all six production departments (Modeling, Texturing, Rigging, Animation, FX, Compositing).

## Architecture overview

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


