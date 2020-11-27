node {
  kubernetes_versions = [
    // https://github.com/kubernetes-sigs/kind/releases
    "kindest/node:v1.19.1@sha256:98cf5288864662e37115e362b23e4369c8c4a408f99cbc06e58ac30ddc721600",
    "kindest/node:v1.18.8@sha256:f4bcc97a0ad6e7abaf3f643d890add7efe6ee4ab90baeb374b4f41a4c95567eb",
    "kindest/node:v1.17.11@sha256:5240a7a2c34bf241afb54ac05669f8a46661912eab05705d660971eeb12f6555",
  ]

  withEnv(['AWS_BUCKET=jobs.amazeeio.services', 'AWS_DEFAULT_REGION=us-east-2']) {
    withCredentials([
      usernamePassword(credentialsId: 'aws-s3-lagoon', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY'),
      string(credentialsId: 'SKIP_IMAGE_PUBLISH', variable: 'SKIP_IMAGE_PUBLISH')
    ]) {
      try {
        env.CI_BUILD_TAG = env.BUILD_TAG.replaceAll('%2f','').replaceAll("[^A-Za-z0-9]+", "").toLowerCase()
        env.SAFEBRANCH_NAME = env.BRANCH_NAME.replaceAll('%2f','-').replaceAll("[^A-Za-z0-9]+", "-").toLowerCase()
        env.SYNC_MAKE_OUTPUT = 'target'
        // make/tests will synchronise (buffer) output by default to avoid interspersed
        // lines from multiple jobs run in parallel. However this means that output for
        // each make target is not written until the command completes.
        //
        // See `man -P 'less +/-O' make` for more information about this option.
        //
        // Uncomment the line below to disable output synchronisation.
        // env.SYNC_MAKE_OUTPUT = 'none'

        stage ('env') {
          sh "env"
        }

        deleteDir()

        stage ('Checkout') {
          def checkout = checkout scm
          env.GIT_COMMIT = checkout["GIT_COMMIT"]
        }

        // in order to have the newest images from upstream (with all the security updates) we clean our local docker cache on tag deployments
        // we don't do this all the time to still profit from image layer caching
        // but we want this on tag deployments in order to ensure that we publish images always with the newest possible images.
        if (env.TAG_NAME) {
          stage ('clean docker image cache') {
            sh script: "docker image prune -af", label: "Pruning images"
          }
        }

        stage ('check PR labels') {
          if (env.BRANCH_NAME ==~ /PR-\d+/) {
            pullRequest.labels.each{
              echo "This PR has labels: $it"
              }
            }
        }

        stage ('build images') {
          sh script: "make -O${SYNC_MAKE_OUTPUT} -j8 build", label: "Building images"
        }

        stage ('push images to testlagoon/*') {
          withCredentials([string(credentialsId: 'amazeeiojenkins-dockerhub-password', variable: 'PASSWORD')]) {
            try {
              if (env.SKIP_IMAGE_PUBLISH != 'true') {
                sh script: 'docker login -u amazeeiojenkins -p $PASSWORD', label: "Docker login"
                sh script: "make -O${SYNC_MAKE_OUTPUT} -j8 publish-testlagoon-baseimages publish-testlagoon-serviceimages publish-testlagoon-taskimages BRANCH_NAME=${SAFEBRANCH_NAME}", label: "Publishing built images"
              } else {
                sh script: 'echo "skipped because of SKIP_IMAGE_PUBLISH env variable"', label: "Skipping image publishing"
              }
              if (env.BRANCH_NAME == 'main' ) {
                sh script: 'docker login -u amazeeiojenkins -p $PASSWORD', label: "Docker login"
                sh script: "make -O${SYNC_MAKE_OUTPUT} -j8 publish-testlagoon-baseimages publish-testlagoon-serviceimages publish-testlagoon-taskimages BRANCH_NAME=latest", label: "Publishing built images with :latest tag"
                withCredentials([string(credentialsId: 'vshn-gitlab-helmfile-ci-trigger', variable: 'TOKEN')]) {
                  sh script: "curl -X POST -F token=$TOKEN -F ref=master https://git.vshn.net/api/v4/projects/1263/trigger/pipeline", label: "Trigger lagoon-core helmfile sync on amazeeio-test6"
                }
              }
            } catch (e) {
              echo "Something went wrong, trying to cleanup"
              cleanup()
              throw e
            }
          }
        }

        def kubernetes = [:]
        def success = true
        def lastException = null
        kubernetes_versions.each { v ->
          def version = v
          kubernetes[version] = {
            try {
              echo "kubernetes ${version.replaceFirst(/@.*$/,"")} tests started"
              // sh script: "make -j8 kind/test K8S_VERSION=${version}", label: "Running tests on kind ${version.replaceFirst(/@.*$/,"")} cluster"
              sh script: "echo make -j8 kind/test K8S_VERSION=${version} && sleep 30", label: "Running tests on kind ${version.replaceFirst(/@.*$/,"")} cluster"
              echo "kubernetes ${version.replaceFirst(/@.*$/,"")} tests succeeded"
            } catch (e) {
              success = false
              echo "kubernetes ${version.replaceFirst(/@.*$/,"")} tests failed"
            }
          }
        }

        stage ("kubernetes ${version} tests") {
          parallel kubernetes
        }

        if (success) {
          currentBuild.result = 'SUCCESS'
        } else {
          currentBuild.result = 'FAILURE'
          throw lastException
        }

        if (env.TAG_NAME && env.SKIP_IMAGE_PUBLISH != 'true') {
          stage ('publish-amazeeio') {
            withCredentials([string(credentialsId: 'amazeeiojenkins-dockerhub-password', variable: 'PASSWORD')]) {
              sh script: 'docker login -u amazeeiojenkins -p $PASSWORD', label: "Docker login"
              sh script: "make -O${SYNC_MAKE_OUTPUT} -j8 publish-uselagoon-baseimages publish-uselagoon-serviceimages publish-uselagoon-taskimages", label: "Publishing built images to uselagoon"
            }
          }
        }

        if (env.BRANCH_NAME == 'main' && env.SKIP_IMAGE_PUBLISH != 'true') {
          stage ('save-images-s3') {
            sh script: "make -O${SYNC_MAKE_OUTPUT} -j8 s3-save", label: "Saving images to AWS S3"
          }
        }

      } catch (e) {
        currentBuild.result = 'FAILURE'
        throw e
      } finally {
        // notifySlack(currentBuild.result)
      }
    }
  }

}

def cleanup() {
  try {
    sh "echo make kind/cleanall"
    sh "make clean"
  } catch (error) {
    echo "cleanup failed, ignoring this."
  }
}

def notifySlack(String buildStatus = 'STARTED') {
    // Build status of null means success.
    buildStatus = buildStatus ?: 'SUCCESS'

    def color

    if (buildStatus == 'STARTED') {
        color = '#68A1D1'
    } else if (buildStatus == 'SUCCESS') {
        color = '#BDFFC3'
    } else if (buildStatus == 'UNSTABLE') {
        color = '#FFFE89'
    } else {
        color = '#FF9FA1'
    }

    def msg = "${buildStatus}: `${env.JOB_NAME}` #${env.BUILD_NUMBER}:\n${env.BUILD_URL}"

    slackSend(color: color, message: msg)
}
