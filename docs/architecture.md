# Architecture

~~~mermaid
flowchart TD
    Dev[Developer pushes code] --> J[Jenkins pipeline]
    J --> T[Pytest tests]
    T --> SQ[SonarQube analysis and quality gate]
    SQ --> D[Build Docker image]
    D --> ECR[Amazon ECR image repository]
    ECR --> LT[EC2 Launch Template]
    LT --> ASG[Auto Scaling Group]
    Internet[Users] --> ALB[Application Load Balancer]
    ALB --> TG[Target group health check: GET /health]
    TG --> EC2[EC2 instance running Flask container]
    EC2 --> App[IT Help Desk UI and ticket endpoints]
    Schedule[CloudWatch Events schedule: every 5 minutes] --> Lambda[Recovery Lambda]
    Lambda --> ASG
    Lambda --> EC2
    TG -. unhealthy target .-> Lambda
    ASG -. replacement instance .-> LT
~~~

## Recovery behavior

1. The CloudWatch Events (EventBridge) schedule invokes the recovery Lambda every five minutes.
2. Lambda discovers current InService instances from the Auto Scaling Group; it does not hard-code an EC2 instance ID.
3. It checks EC2 system/instance status and Application Load Balancer target health.
4. Instances younger than the five-minute launch grace period are skipped to avoid terminating instances while user data and Docker are starting.
5. An older instance with an impaired EC2 status check or an unhealthy ALB target is terminated with ShouldDecrementDesiredCapacity = false.
6. The Auto Scaling Group launches a replacement to restore desired capacity. Launch-template user data installs Docker, authenticates to ECR using the instance profile, pulls the configured image tag, and runs the container on port 5000.
7. Recovery decisions are written to the Lambda CloudWatch Logs group.

This is a scheduled health-check and replacement workflow, not a direct EC2 reboot. Termination lets the ASG replace an unhealthy instance and re-run its bootstrapping. It does not remediate an application bug present in the image.

**Important:** Tickets are held in an in-memory Python list and disappear when the application process or instance restarts. Use durable storage before treating this as a production help-desk service.
