pipeline {
    // run on jenkins nodes that have java 8 label
    agent any 
    // global env variables
    environment {
        EMAIL_RECIPIENTS = 'shahrooq123@gmail.com'
    }
    stages {
        stage('Build with unit testing') {
            steps {
                // Run the maven build
                script {
                    echo 'Pulling...' + env.BRANCH_NAME
                    if (isUnix()) {
                        def targetVersion = getDevVersion()
                        print 'target build version...'
                        print targetVersion
                        sh "mvn -Dintegration-tests.skip=true -Dbuild.number=${targetVersion} clean package"
                        def pom = readMavenPom file: 'pom.xml'
                        // get the current development version
                        developmentArtifactVersion = "${pom.version}-${targetVersion}"
                        print pom.version
                        // execute the unit testing and collect the reports
                        junit '**//*target/surefire-reports/TEST-*.xml'
                        archive 'target*//*.jar'
                    } else {
                        bat(/mvn -Dintegration-tests.skip=true clean package/)
                        def pom = readMavenPom file: 'pom.xml'
                        print pom.version
                        junit '**//*target/surefire-reports/TEST-*.xml'
                        archive 'target*//*.jar'
                    }
                }
            }
        }

        stage('Integration tests') {
            // Run integration test
            steps {
                script {
                    if (isUnix()) {
                        // just to trigger the integration test without unit testing
                        sh "mvn verify -Dunit-tests.skip=true"
                    } else {
                        bat(/mvn verify -Dunit-tests.skip=true/)
                    }
                }
                // cucumber reports collection
                cucumber buildStatus: null, fileIncludePattern: '**/cucumber.json', jsonReportDirectory: 'target', sortingMethod: 'ALPHABETICAL'
            }
        }

        stage('Sonar scan execution') {
            // Run the sonar scan
            steps {
                script {
                    withSonarQubeEnv {
                        sh "mvn verify sonar:sonar -Dintegration-tests.skip=true -Dmaven.test.failure.ignore=true"
                    }
                }
            }
        }

        // waiting for sonar results based into the configured web hook in Sonar server
        stage('Sonar scan result check') {
            steps {
                timeout(time: 2, unit: 'MINUTES') {
                    retry(3) {
                        script {
                            def qg = waitForQualityGate()
                            if (qg.status != 'OK') {
                                error "Pipeline aborted due to quality gate failure: ${qg.status}"
                            }
                        }
                    }
                }
            }
        }

        stage('Development deploy approval and deployment') {
            steps {
                script {
                    if (currentBuild.result == null || currentBuild.result == 'SUCCESS') {
                        timeout(time: 3, unit: 'MINUTES') {
                            input message: 'Approve deployment?'
                        }
                        timeout(time: 2, unit: 'MINUTES') {
                            if (developmentArtifactVersion != null && !developmentArtifactVersion.isEmpty()) {
                                def jarName = "application-${developmentArtifactVersion}.jar"
                                echo "the application is deploying ${jarName}"
                                build job: 'ApplicationToDev', parameters: [[$class: 'StringParameterValue', name: 'jarName', value: jarName]]
                                echo 'the application is deployed!'
                            } else {
                                error 'the application is not deployed as development version is null!'
                            }
                        }
                    }
                }
            }
        }

        stage('DEV sanity check') {
            steps {
                sleep(45) // wait for deployment
                script {
                    if (currentBuild.result == null || currentBuild.result == 'SUCCESS') {
                        timeout(time: 1, unit: 'MINUTES') {
                            script {
                                sh "mvn -Dtest=ApplicationSanityCheck_ITT surefire:test"
                            }
                        }
                    }
                }
            }
        }

        stage('Release and publish artifact') {
            when {
                branch 'master'
            }
            steps {
                script {
                    if (currentBuild.result == null || currentBuild.result == 'SUCCESS') {
                        def v = getReleaseVersion()
                        releasedVersion = v;
                        if (v) {
                            echo "Building version ${v} - released version is ${releasedVersion}"
                        }
                        sshagent(['0000000-3b5a-454e-a8e6-c6b6114d36000']) {
                            sh "git tag -f v${v}"
                            sh "git push -f --tags"
                        }
                        sh "mvn -Dmaven.test.skip=true versions:set -DgenerateBackupPoms=false -DnewVersion=${v}"
                        sh "mvn -Dmaven.test.skip=true clean deploy"
                    } else {
                        error "Release is not possible as the build is not successful"
                    }
                }
            }
        }

        stage('Deploy to Acceptance') {
            when {
                branch 'master'
            }
            steps {
                script {
                    if (currentBuild.result == null || currentBuild.result == 'SUCCESS') {
                        timeout(time: 3, unit: 'MINUTES') {
                            input message: 'Approve deployment to UAT?'
                        }
                        timeout(time: 3, unit: 'MINUTES') {
                            if (releasedVersion != null && !releasedVersion.isEmpty()) {
                                def jarName = "application-${releasedVersion}.jar"
                                echo "the application is deploying ${jarName}"
                                build job: 'AApplicationToACC', parameters: [[$class: 'StringParameterValue', name: 'jarName', value: jarName], [$class: 'StringParameterValue', name: 'appVersion', value: releasedVersion]]
                                echo 'the application is deployed!'
                            } else {
                                error 'the application is not deployed as released version is null!'
                            }
                        }
                    }
                }
            }
        }

        stage('ACC E2E tests') {
            when {
                branch 'master'
            }
            steps {
                sleep(45) // wait for deployment
                script {
                    if (currentBuild.result == null || currentBuild.result == 'SUCCESS') {
                        timeout(time: 1, unit: 'MINUTES') {
                            script {
                                sh "mvn -Dtest=ApplicationE2E surefire:test"
                            }
                        }
                    }
                }
            }
        }
    }
    post {
        always {
            deleteDir() // Cleanup workspace
        }
        success {
            sendEmail("Successful")
        }
        unstable {
            sendEmail("Unstable")
        }
        failure {
            sendEmail("Failed")
        }
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '5'))
        timeout(time: 25, unit: 'MINUTES')
    }
}

def developmentArtifactVersion = ''
def releasedVersion = ''

@NonCPS
def getChangeString() {
    MAX_MSG_LEN = 100
    def changeString = ""
    echo "Gathering SCM changes"
    def changeLogSets = currentBuild.changeSets
    for (int i = 0; i < changeLogSets.size(); i++) {
        def entries = changeLogSets[i].items
        for (int j = 0; j < entries.length; j++) {
            def entry = entries[j]
            truncated_msg = entry.msg.take(MAX_MSG_LEN)
            changeString += " - ${truncated_msg} [${entry.author}]\n"
        }
    }
    if (!changeString) {
        changeString = " - No new changes"
    }
    return changeString
}

def sendEmail(status) {
    mail(
        to: "$EMAIL_RECIPIENTS",
        subject: "Build $BUILD_NUMBER - " + status + " (${currentBuild.fullDisplayName})",
        body: "Changes:\n " + getChangeString() + "\n\n Check console output at: $BUILD_URL/console" + "\n"
    )
}

def getDevVersion() {
    def gitCommit = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
    def versionNumber;
    if (gitCommit == null) {
        versionNumber = env.BUILD_NUMBER;
    } else {
        versionNumber = gitCommit.take(8);
    }
    print 'build  versions...'
    print versionNumber
    return versionNumber
}

def getReleaseVersion() {
    def pom = readMavenPom file: 'pom.xml'
    def gitCommit = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
    def versionNumber;
    if (gitCommit == null) {
        versionNumber = env.BUILD_NUMBER;
    } else {
        versionNumber = gitCommit.take(8);
    }
    return pom.version.replace("-SNAPSHOT", ".${versionNumber}")
}
