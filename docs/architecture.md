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
    TG -. unhealthy instance .-> ASG
    ASG -. replace unhealthy EC2 .-> LT
~~~

## Recovery behavior

1. The ALB periodically requests GET /health from registered instances.
2. If an instance fails target-group health checks, the ALB marks it unhealthy.
3. The Auto Scaling Group uses ELB health checks and can replace an unhealthy instance to restore desired capacity.
4. A replacement instance uses Launch Template user data to install Docker, authenticate to ECR with its IAM instance profile, and start the selected image tag.

**Important:** This is instance-level recovery, not durable ticket storage. The current Flask app stores tickets in memory, so tickets disappear when a process or instance restarts. Use a database before treating this as a production help-desk service.
