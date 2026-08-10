// Jenkinsfile
// Manually-triggered declarative pipeline that builds the hello-world image, pushes
// it to ECR, deploys it to the application ECS service, and runs a post-deploy
// health check. Emails the outcome for ALL results (success/failure/aborted),
// per challenge requirement #3.
//
// This pipeline is designed to run as an ECS container (the Jenkins service defined
// in Terraform). Parameters let a reviewer point it at their account without edits.

pipeline {
  agent any

  // Manual trigger only: no SCM polling / webhooks.
  options {
    disableConcurrentBuilds()
    timestamps()
  }

  parameters {
    string(name: 'AWS_REGION',   defaultValue: 'eu-central-1',                 description: 'AWS region')
    string(name: 'ECR_REPO',     defaultValue: '',                             description: 'ECR repository URL (from terraform output ecr_repository_url)')
    string(name: 'ECS_CLUSTER',  defaultValue: '',                             description: 'App ECS cluster name')
    string(name: 'ECS_SERVICE',  defaultValue: '',                             description: 'App ECS service name')
    string(name: 'APP_URL',      defaultValue: '',                             description: 'App ALB URL for the post-deploy health check')
    string(name: 'LOG_BUCKET',   defaultValue: '',                             description: 'S3 bucket for pipeline logs')
    string(name: 'NOTIFY_EMAIL', defaultValue: 'cloud-ops@example.com',        description: 'Where to email pipeline results')
  }

  environment {
    IMAGE_TAG = "${env.BUILD_NUMBER}"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build image') {
      steps {
        script {
          dockerLogged("build", "docker build --build-arg BUILD_TAG=${IMAGE_TAG} -f docker/hello-world/Dockerfile -t ${params.ECR_REPO}:${IMAGE_TAG} docker/hello-world")
        }
      }
    }

    stage('Login to ECR') {
      steps {
        script {
          def registry = params.ECR_REPO.tokenize('/')[0]
          sh "aws ecr get-login-password --region ${params.AWS_REGION} | docker login --username AWS --password-stdin ${registry}"
        }
      }
    }

    stage('Push image') {
      steps {
        script {
          dockerLogged("push", "docker push ${params.ECR_REPO}:${IMAGE_TAG}")
        }
      }
    }

    stage('Deploy to ECS') {
      steps {
        script {
          // Force a new deployment so the service pulls the freshly-pushed tag.
          sh """
            aws ecs update-service \
              --region ${params.AWS_REGION} \
              --cluster ${params.ECS_CLUSTER} \
              --service ${params.ECS_SERVICE} \
              --force-new-deployment
          """
        }
      }
    }

    stage('Verify health') {
      steps {
        sh "chmod +x scripts/verify_health.sh"
        sh "scripts/verify_health.sh ${params.APP_URL}health 200 20 6"
      }
    }
  }

  // Email results for ALL outcomes (challenge requirement #3).
  post {
    success {
      emailext(
        to: "${params.NOTIFY_EMAIL}",
        subject: "SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
        body: "Deployment succeeded. Image ${params.ECR_REPO}:${IMAGE_TAG} is live.\n${env.BUILD_URL}"
      )
    }
    failure {
      emailext(
        to: "${params.NOTIFY_EMAIL}",
        subject: "FAILURE: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
        body: "Pipeline failed. See console: ${env.BUILD_URL}"
      )
    }
    aborted {
      emailext(
        to: "${params.NOTIFY_EMAIL}",
        subject: "ABORTED: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
        body: "Pipeline was aborted. See console: ${env.BUILD_URL}"
      )
    }
  }
}

// dockerLogged wraps a docker command, capturing its full output and shipping that
// output to S3.
//
// FLAW (pipeline): every single docker command's full stdout/stderr is written to its
// own timestamped S3 object on every run. Docker build/push output is large and
// highly repetitive across builds, so this uploads redundant multi-KB log objects per
// command per build, steadily inflating S3 storage + PUT-request costs. It does NOT
// affect correctness — builds/pushes still succeed. This flaw is intentionally
// interlinked with the others (over-allocated CPU -> more instances; redundant health
// probes -> more log lines) to form a cost-bloat theme. Fix: log to the Jenkins
// console/CloudWatch and archive a single consolidated log per build instead.
def dockerLogged(String label, String command) {
  def logFile = "docker-${label}-${env.BUILD_NUMBER}.log"
  sh "set -o pipefail; ${command} 2>&1 | tee ${logFile}"
  if (params.LOG_BUCKET?.trim()) {
    def key = "pipeline/${env.JOB_NAME}/${env.BUILD_NUMBER}/${label}-$(date +%s).log"
    sh "aws s3 cp ${logFile} s3://${params.LOG_BUCKET}/${key} --region ${params.AWS_REGION}"
  }
}
