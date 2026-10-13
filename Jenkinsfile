
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 30, unit: 'MINUTES')
    }

    environment {
        AWS_DEFAULT_REGION = 'ap-south-1'
        AWS_ACCOUNT_ID = '495234635542'
        ECR_REGISTRY = '495234635542.dkr.ecr.ap-south-1.amazonaws.com'
        ECR_REPOSITORY = 'aws-self-healing-help-desk'
        IMAGE_NAME = 'aws-self-healing-help-desk'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Check Tools') {
            steps {
                sh '''
                    set -eu
                    python3 --version
                    python3 -m pip --version
                    docker --version
                    aws --version
                '''
            }
        }

        stage('Install Dependencies') {
            steps {
                sh '''
                    set -eu
                    python3 -m venv .venv
                    .venv/bin/python -m pip install --upgrade pip
                    .venv/bin/python -m pip install -r requirements.txt
                '''
            }
        }

        stage('Run Tests') {
            steps {
                sh '''
                    set -eu
                    .venv/bin/python -m pytest -v
                '''
            }
        }

        stage('SonarQube Analysis') {
            steps {
                script {
                    def scannerHome = tool 'SonarScanner'

                    withSonarQubeEnv('SonarQube') {
                        sh "${scannerHome}/bin/sonar-scanner"
                    }
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Docker Build') {
            steps {
                sh '''
                    set -eu
                    docker build \
                      -t "$IMAGE_NAME:$BUILD_NUMBER" .
                '''
            }
        }

        stage('Push to Amazon ECR') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-ecr-credentials',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    sh '''
                        set -eu
                        set +x

                        aws ecr get-login-password \
                          --region "$AWS_DEFAULT_REGION" |
                          docker login \
                            --username AWS \
                            --password-stdin "$ECR_REGISTRY"

                        docker tag \
                          "$IMAGE_NAME:$BUILD_NUMBER" \
                          "$ECR_REGISTRY/$ECR_REPOSITORY:$BUILD_NUMBER"

                        docker push \
                          "$ECR_REGISTRY/$ECR_REPOSITORY:$BUILD_NUMBER"

                        docker tag \
                          "$IMAGE_NAME:$BUILD_NUMBER" \
                          "$ECR_REGISTRY/$ECR_REPOSITORY:latest"
                        docker push "$ECR_REGISTRY/$ECR_REPOSITORY:latest"

                        docker logout "$ECR_REGISTRY"
                    '''
                }
            }
        }

        stage('Deploy to EC2 Auto Scaling Group') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-ecr-credentials',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    sh '''
                        set -eu
                        set +x

                        ASG_NAME="self-healing-help-desk-asg"

                        echo "Checking that Terraform-created Auto Scaling Group exists..."
                        aws autoscaling describe-auto-scaling-groups \\
                          --auto-scaling-group-names "$ASG_NAME" \\
                          --region "$AWS_DEFAULT_REGION" \\
                          --query 'AutoScalingGroups[0].AutoScalingGroupName' \\
                          --output text | grep -qx "$ASG_NAME"

                        echo "Requesting one application instance..."
                        aws autoscaling update-auto-scaling-group \\
                          --auto-scaling-group-name "$ASG_NAME" \\
                          --min-size 1 \\
                          --desired-capacity 1 \\
                          --region "$AWS_DEFAULT_REGION"

                        echo "Refreshing instances so they start with the image just pushed to ECR..."
                        REFRESH_ID=$(aws autoscaling start-instance-refresh \\
                          --auto-scaling-group-name "$ASG_NAME" \\
                          --region "$AWS_DEFAULT_REGION" \\
                          --preferences '{"MinHealthyPercentage":0,"MaxHealthyPercentage":100,"InstanceWarmup":240}' \\
                          --query 'InstanceRefreshId' \\
                          --output text)

                        echo "Instance refresh ID: $REFRESH_ID"
                        i=0
                        while [ "$i" -lt 100 ]; do
                          STATUS=$(aws autoscaling describe-instance-refreshes \\
                            --auto-scaling-group-name "$ASG_NAME" \\
                            --instance-refresh-ids "$REFRESH_ID" \\
                            --region "$AWS_DEFAULT_REGION" \\
                            --query 'InstanceRefreshes[0].Status' \\
                            --output text)
                          echo "Instance refresh status: $STATUS"

                          if [ "$STATUS" = "Successful" ]; then
                            echo "EC2 deployment completed. Verify the ALB target health and /health endpoint."
                            exit 0
                          fi

                          case "$STATUS" in
                            Failed|Cancelled|RollbackFailed|RollbackSuccessful|RollbackCancelled)
                              echo "Instance refresh ended with status: $STATUS"
                              exit 1
                              ;;
                          esac

                          i=$((i + 1))
                          sleep 12
                        done

                        echo "Timed out waiting for deployment. Check Auto Scaling activity, EC2 user-data logs, and ALB target health."
                        exit 1
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'SUCCESS: Tests, SonarQube, Quality Gate, Docker build and ECR push completed.'
        }

        failure {
            echo 'FAILED: Check the failed stage in the Jenkins console output.'
        }

        always {
            echo "Build number: ${BUILD_NUMBER}"
        }
    }
}
