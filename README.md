
# AWS Self-Healing IT Help Desk

A hands-on AWS project that combines a Flask-based IT support ticket portal, Docker, Jenkins CI/CD, SonarQube quality checks, Amazon ECR, Terraform, and automated EC2 instance recovery.

The application runs on EC2 instances managed by an Auto Scaling Group (ASG) and receives traffic through an Application Load Balancer (ALB). A scheduled AWS Lambda function checks EC2 status and ALB target health, then requests replacement of qualifying unhealthy instances through Auto Scaling.

> **Project status:** Application deployment, Jenkins pipeline, AWS health checks, scheduled Lambda execution, and all 7 automated tests have been verified. End-to-end Lambda-triggered instance recovery remains to be demonstrated.

## Highlights

- Flask-based Help Desk dashboard for creating and viewing support tickets.
- `/health` endpoint for application health checks.
- Docker-based application packaging.
- Jenkins pipeline for tests, SonarQube analysis, quality gate, Docker build, ECR push, and ASG deployment.
- Terraform-managed AWS infrastructure.
- Application Load Balancer and target-group health checks.
- EC2 Auto Scaling Group with configurable desired capacity.
- Scheduled Lambda health checks through Amazon EventBridge.
- CloudWatch Logs for troubleshooting and execution evidence.
- Automated tests using pytest.

## Architecture

![AWS Self-Healing IT Help Desk architecture](docs/architecture.svg)

Editable architecture source: [docs/architecture.md](docs/architecture.md)

### Request flow

1. A user opens the Help Desk URL.
2. The Application Load Balancer receives the HTTP request.
3. The ALB forwards traffic to a healthy registered EC2 target on port `5000`.
4. A Docker container runs the Flask application.
5. The target group's `/health` endpoint provides the HTTP health-check response.

### Recovery flow

1. Amazon EventBridge invokes the recovery Lambda on its configured schedule.
2. Lambda retrieves the ASG's `InService` instances.
3. It checks EC2 system and instance status, launch times, and ALB target health.
4. It skips instances that are still within the configured launch grace period.
5. If an eligible instance has an impaired EC2 status check or an `unhealthy` ALB target state, Lambda requests termination through Auto Scaling without decrementing desired capacity.
6. The ASG is expected to launch a replacement instance.
7. The new instance and ALB target must be checked to confirm recovery.

**Important:** A successful Lambda invocation alone does not prove that automatic recovery occurred. End-to-end recovery is confirmed only after observing the unhealthy condition, Lambda's replacement action, a new instance entering `InService`, and a healthy ALB target.

## Technology Stack

| Category | Technologies |
|---|---|
| Application | Python, Flask, Jinja templates |
| Containers | Docker |
| CI/CD | Jenkins |
| Code quality | SonarQube |
| Testing | pytest |
| Container registry | Amazon ECR |
| Compute | Amazon EC2, Auto Scaling Group |
| Traffic management | Application Load Balancer, target group |
| Recovery automation | AWS Lambda, Amazon EventBridge |
| Monitoring | Amazon CloudWatch Logs |
| Infrastructure as Code | Terraform |
| Networking and access | VPC, subnets, security groups, IAM |

## Repository Structure

```text
.
├── app/
│   └── main.py
├── templates/
│   └── index.html
├── tests/
│   ├── test_main.py
│   └── test_lambda_recovery.py
├── terraform/
│   ├── networking.tf
│   ├── security.tf
│   ├── iam.tf
│   ├── compute.tf
│   ├── lambda.tf
│   ├── lambda_recovery.py
│   ├── user_data.sh.tftpl
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── docs/
│   ├── architecture.md
│   ├── architecture.svg
│   └── screenshots/
├── Dockerfile
├── Dockerfile.jenkins
├── Jenkinsfile
├── requirements.txt
├── sonar-project.properties
└── README.md
```

*This structure reflects the project layout; check the repository if files have changed.*

## Prerequisites

- Git
- Python compatible with the project's dependencies
- Docker
- AWS CLI
- Terraform
- An AWS account with permissions for the resources in the Terraform plan
- Jenkins and SonarQube configuration if running the full pipeline

The project has been deployed in AWS Mumbai (`ap-south-1`).

## Run Locally

Clone the repository:

```bash
git clone https://github.com/venkatasaikirannadupuru/aws-self-healing-help-desk.git
cd aws-self-healing-help-desk
```

Create and activate a virtual environment.

**Windows Git Bash:**

```bash
python -m venv .venv
source .venv/Scripts/activate
```

**Linux/macOS:**

```bash
python3 -m venv .venv
source .venv/bin/activate
```

Install dependencies:

```bash
python -m pip install -r requirements.txt
```

Start the application using the project's configured entry point:

```bash
python -m app.main
```

Open `http://127.0.0.1:5000`.

Health endpoint: `http://127.0.0.1:5000/health`

If the current application version uses a different entry point, use the run command defined by that version.

## Run Tests

Run the tests from the **repository root**:

```bash
python -m pytest -v tests/
```

Latest recorded test result:

```text
7 passed in 2.45s
```

The test suite covers:

- Home page rendering
- Health endpoint
- Ticket creation
- Required ticket fields
- Behavior when the ASG is not found
- Replacement request for an old unhealthy target
- Skipping an instance within the launch grace period

The Lambda tests validate recovery logic using test doubles/mocks. They do not independently prove that a real AWS instance was replaced.

## Build and Run with Docker

Build the image:

```bash
docker build -t helpdesk:local .
```

Run it:

```bash
docker run --rm -p 5000:5000 --name helpdesk-local helpdesk:local
```

Open `http://127.0.0.1:5000`.

## AWS Deployment

> **Cost and security warning:** AWS resources such as EC2, an Application Load Balancer, ECR storage, and CloudWatch may incur charges. This demo uses HTTP and public-subnet infrastructure; do not use it unchanged for sensitive production traffic.

### 1. Configure Terraform

Configure AWS credentials securely, then:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -check
terraform validate
terraform plan
```

Review the plan carefully before applying:

```bash
terraform apply
```

Follow the bootstrap procedure in your Terraform configuration and Jenkins pipeline. If the launch template pulls an image from ECR during startup, ensure that the image has been published before launching application instances.

### 2. Run the Jenkins pipeline

The pipeline is configured to perform these steps:

1. Check out the source code.
2. Check required tools.
3. Install dependencies.
4. Run automated tests.
5. Run SonarQube analysis.
6. Evaluate the quality gate.
7. Build the Docker image.
8. Push the image to Amazon ECR.
9. Deploy through the configured ASG instance-refresh workflow.

The recorded successful Jenkins build was `help-desk-ci-pipeline` build **#13**.

Ensure Jenkins has the required tool configurations, AWS credentials, Docker access, and SonarQube connection. Use least-privilege permissions and never commit secrets to Git.

A Jenkins deployment or successful instance refresh is separate from Lambda-triggered self-healing.

### 3. Verify the AWS deployment

- Confirm the ASG has the intended desired capacity.
- Confirm the EC2 instance reaches `InService`.
- Confirm the ALB target becomes `Healthy`.
- Open the Terraform output `helpdesk_url`.
- Test the application's `/health` endpoint.
- Review Lambda logs and ASG activity history when testing recovery.

## Self-Healing Configuration

The recovery function is located at `terraform/lambda_recovery.py`.

| Environment variable | Purpose |
|---|---|
| `ASG_NAME` | Name of the Auto Scaling Group to inspect |
| `TARGET_GROUP_ARN` | ARN of the ALB target group |
| `GRACE_PERIOD_SECONDS` | Minimum instance age before recovery evaluation |

Current configured grace period: **300 seconds (5 minutes)**.

The function checks:

- EC2 system status is `impaired`.
- EC2 instance status is `impaired`.
- ALB target health state is `unhealthy`.

When an eligible instance meets a configured failure condition, Lambda calls Auto Scaling to terminate the instance without reducing desired capacity. The ASG can then launch a replacement.

### Recovery Test Checklist

In a sandbox environment where temporary downtime is acceptable:

- [ ] Record the current instance ID and confirm its target is healthy.
- [ ] Confirm the EventBridge schedule and Lambda permissions.
- [ ] Trigger a controlled unhealthy condition.
- [ ] Find the recovery decision in CloudWatch Logs.
- [ ] Check Auto Scaling activity history for the replacement.
- [ ] Verify the replacement instance reaches `InService`.
- [ ] Verify the ALB target becomes `Healthy`.
- [ ] Confirm the application responds again.

The Lambda schedule runs every five minutes. Detection and recovery may take several minutes, depending on health-check thresholds, scheduling, and the grace period. This is not a sub-minute recovery guarantee.

## Monitoring and Troubleshooting

Open:

**AWS Console → Lambda → `self-healing-help-desk-recovery` → Monitor → View CloudWatch logs**

Useful log messages include:

- `Skipping ... within launch grace period.` — the instance is too new for recovery evaluation.
- `Replacing ...` — Lambda has requested instance replacement.
- `No InService instances ...` — no eligible instances were found in the ASG response.
- `was not found` — the configured ASG name could not be found.

Also inspect:

- EC2 status checks
- ASG Activity history
- ALB target health reason
- Docker container state and EC2 bootstrap logs
- Lambda execution role permissions
- Lambda environment variables

## Known Limitations

- **In-memory tickets:** Ticket data is stored in process memory and is lost when the application restarts. DynamoDB or RDS could provide persistence.
- **Instance recovery, not code repair:** The Lambda replaces an unhealthy instance; it does not diagnose or fix application-code bugs.
- **Polling interval:** The scheduled recovery process may take several minutes to detect a failure.
- **HTTP-only demo:** HTTPS with ACM should be configured before exposing a production application.
- **Networking:** Public-subnet instances and outbound access are used for the demo. A production design should evaluate private subnets, VPC endpoints or NAT, and tighter egress rules.
- **IAM:** Review and restrict permissions before any production use.

## Cleanup

Review the Terraform destroy plan before deleting resources:

```bash
cd terraform
terraform plan -destroy
```

If the plan contains only resources belonging to this project and you intend to remove them:

```bash
terraform destroy
```

Confirm the plan before proceeding. Resources outside the Terraform state, including leftover ECR images, may need separate cleanup.

## Author

**Venkata Sai Kiran Nadupuru**

GitHub: [@venkatasaikirannadupuru](https://github.com/venkatasaikirannadupuru)
