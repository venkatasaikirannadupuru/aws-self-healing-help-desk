# AWS Self-Healing IT Help Desk

A portfolio project combining a Flask-based IT support ticket portal, Docker packaging, Jenkins CI, SonarQube quality checks, Amazon ECR, and Terraform-managed AWS infrastructure.

> **Scope note:** the Terraform architecture implements *instance-level recovery* using an Application Load Balancer health check and an EC2 Auto Scaling Group. It is not yet a full application-level remediation platform. Tickets are currently held in process memory and are not durable across restarts.

## Project highlights

- Responsive Help Desk dashboard for creating and reviewing support tickets.
- Flask health endpoint: `GET /health`.
- Automated test stage using pytest.
- Jenkins stages for tests, SonarQube analysis, quality gate, Docker build, and Amazon ECR push.
- Terraform-managed VPC, public subnets in two Availability Zones, internet gateway, security groups, IAM instance profile, ECR, ALB, target group, launch template, and Auto Scaling Group.
- ALB target-group health checks and Auto Scaling Group ELB health checks for replacing unhealthy instances.
- Infrastructure architecture diagram and reproducible local setup instructions.

## Architecture

![AWS self-healing Help Desk architecture](docs/architecture.svg)

The editable Mermaid source is available in [docs/architecture.md](docs/architecture.md).

## Technology stack

| Area | Tools |
|---|---|
| Application | Python, Flask, Jinja templates |
| Container | Docker |
| CI and quality | Jenkins, pytest, SonarQube |
| Image registry | Amazon ECR |
| AWS runtime | EC2, Auto Scaling, Application Load Balancer |
| Networking and access | VPC, public subnets, security groups, IAM |
| Infrastructure as Code | Terraform |

## Repository structure

```text
.
├── app/main.py
├── templates/index.html
├── tests/test_main.py
├── Dockerfile
├── Dockerfile.jenkins
├── Jenkinsfile
├── requirements.txt
├── sonar-project.properties
├── terraform/
│   ├── versions.tf
│   ├── variables.tf
│   ├── networking.tf
│   ├── security.tf
│   ├── iam.tf
│   ├── compute.tf
│   ├── user_data.sh.tftpl
│   ├── outputs.tf
│   └── terraform.tfvars.example
└── docs/
    ├── architecture.md
    ├── architecture.svg
    └── screenshots/
```

## Run locally

Requirements: Python 3.10+ and pip.

```bash
git clone https://github.com/venkatasaikirannadupuru/aws-self-healing-help-desk.git
cd aws-self-healing-help-desk

python -m venv .venv
# Windows Git Bash:
source .venv/Scripts/activate
# Linux/macOS:
# source .venv/bin/activate

python -m pip install -r requirements.txt
python -m app.main
```

Open [http://127.0.0.1:5000](http://127.0.0.1:5000). Health check: [http://127.0.0.1:5000/health](http://127.0.0.1:5000/health).

Run tests:

```bash
python -m pytest -v
```

Run as a container:

```bash
docker build -t helpdesk:local .
docker run --rm -p 5000:5000 helpdesk:local
```

## AWS deployment with Terraform

**Cost and security warning:** applying this configuration creates billable AWS resources, including an Application Load Balancer and EC2 capacity. Review the plan and your AWS budget before applying. Use a sandbox account and destroy resources when finished. The demo uses public subnets and HTTP only; do not use it as-is for sensitive production traffic.

### Prerequisites

- AWS CLI configured for the target account and region.
- Terraform 1.6 or newer.
- Docker and permission to push to Amazon ECR.
- IAM permissions to create the resources in the Terraform plan.

### 1. Create infrastructure without application instances

The ECR repository must exist before Jenkins can push the first image. Start with zero desired EC2 instances:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Set `desired_capacity = 0` in `terraform.tfvars`, then run:

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

### 2. Configure Jenkins and publish the image

The Jenkinsfile expects:
- Jenkins tool named `SonarScanner`.
- SonarQube server configuration named `SonarQube`.
- Jenkins credential ID `aws-ecr-credentials` containing an AWS access key and secret key with least-privilege ECR push permissions.
- Docker, AWS CLI, Python, and pip available on the Jenkins agent.
- The ECR repository created by the first Terraform apply.

Run the pipeline. It runs tests and the SonarQube quality gate before building and pushing the build-number tag and `latest` to ECR.

### 3. Start the application instances

After Jenkins successfully pushes the image, set `desired_capacity = 1` in `terraform.tfvars` and apply:

```bash
terraform plan
terraform apply
terraform output helpdesk_url
```

Open the URL from `helpdesk_url`. Wait for the target group to report healthy targets before testing the UI.

### 4. Verify the self-healing behavior

1. Confirm the target is healthy in EC2 → Target Groups.
2. Confirm the Auto Scaling Group has the desired number of healthy instances.
3. In a sandbox only, perform a controlled instance failure test.
4. Observe the unhealthy target and the Auto Scaling activity history.
5. Verify a replacement instance becomes healthy and the ALB URL recovers.

Do not claim a recovery test passed until it has actually been run and its AWS evidence captured.

## Screenshots

Place real screenshots in `docs/screenshots/`. Suggested captures:

- `helpdesk-dashboard.png` — UI with example ticket data.
- `jenkins-pipeline.png` — successful pipeline and quality gate.
- `target-group-health.png` — target health before and after a test.
- `autoscaling-activity.png` — replacement activity history.

Redact account identifiers or sensitive details where appropriate. See [screenshot guidance](docs/screenshots/README.md). Screenshots are intentionally not fabricated.

## Current limitations and next improvements

- Tickets are stored in an in-memory Python list; a restart clears them. Add DynamoDB or RDS for persistence.
- The current health endpoint confirms the Flask process responds, but does not validate dependencies.
- The demo is HTTP-only. Add HTTPS with ACM and a secure listener before any real deployment.
- Public-subnet instances need outbound internet access for package installation and ECR image pulls. A production design should use private application subnets with appropriate VPC endpoints/NAT and tighter egress rules.
- Add CloudWatch alarms, structured application logs, and notifications if you want observability beyond ALB health checks.
- Consider a separate application-level remediation workflow only after defining the failure signals, safe actions, permissions, and audit trail.

## Cleanup

When finished, set `desired_capacity = 0` and apply before destroying the stack:

```bash
terraform apply
terraform destroy
```

Review the plan carefully. Manually created ECR images or other resources outside this Terraform state may need separate cleanup.

## Author

**Venkata Sai Kiran Nadupuru**  
GitHub: [@venkatasaikirannadupuru](https://github.com/venkatasaikirannadupuru)
