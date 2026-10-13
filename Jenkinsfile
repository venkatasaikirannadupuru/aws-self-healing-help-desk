
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
