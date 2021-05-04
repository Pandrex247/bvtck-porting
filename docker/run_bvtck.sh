#!/bin/bash -xe
#
# Copyright (c) 2018 Oracle and/or its affiliates. All rights reserved.
# Copyright (c) 2019, 2020 Payara Foundation and/or its affiliates. All rights reserved.
#
# This program and the accompanying materials are made available under the
# terms of the Eclipse Public License v. 2.0, which is available at
# http://www.eclipse.org/legal/epl-2.0.
#
# This Source Code may also be made available under the following Secondary
# Licenses when the conditions for such availability set forth in the
# Eclipse Public License v. 2.0 are satisfied: GNU General Public License,
# version 2 with the GNU Classpath Exception, which is available at
# https://www.gnu.org/software/classpath/license.html.
#
# SPDX-License-Identifier: EPL-2.0 OR GPL-2.0 WITH Classpath-exception-2.0

echo Workspace Directory: ${WORKSPACE}

VER="3.0"
if ls ${WORKSPACE}/bundles/*bv-tck*.zip 1> /dev/null 2>&1; then
  unzip -o ${WORKSPACE}/bundles/*bv-tck-payara*.zip -d ${WORKSPACE}
else
  echo "[ERROR] TCK bundle not found"
  exit 1
fi

export TS_HOME=${WORKSPACE}/bv-tck-glassfish-porting

#Install Glassfish
echo "Download and install GlassFish..."
wget --progress=bar:force --no-cache $GF_BUNDLE_URL -O  ${WORKSPACE}/latest-glassfish.zip
unzip -q -o ${WORKSPACE}/latest-glassfish.zip -d ${WORKSPACE}


if [ -z "${BV_TCK_VERSION}" ]; then
  BV_TCK_VERSION=3.0.0
fi

if [ -z "${BV_TCK_BUNDLE_URL}" ]; then
  BV_TCK_BUNDLE_URL=http://download.eclipse.org/ee4j/bean-validation/3.0/beanvalidation-tck-dist-${BV_TCK_VERSION}.zip	

fi

#Install BV TCK dist
echo "Download and unzip BV TCK dist ..."
wget --progress=bar:force --no-cache $BV_TCK_BUNDLE_URL -O  ${WORKSPACE}/latest-beanvalidation-tck-dist.zip
unzip -o  ${WORKSPACE}/latest-beanvalidation-tck-dist.zip -d ${WORKSPACE}/

which ant
ant -version

REPORT=${WORKSPACE}/bvtck-report

mkdir -p ${REPORT}/beanvalidation-$VER-sig
mkdir -p ${REPORT}/beanvalidation-$VER

#Edit Glassfish Security policy
cat ${WORKSPACE}/docker/BV.policy >> ${WORKSPACE}/payara6/glassfish/domains/domain1/config/server.policy

#Edit test properties
sed -i "s#porting.home=.*#porting.home=${TS_HOME}#g" ${TS_HOME}/build.properties
sed -i "s#glassfish.home=.*#glassfish.home=${WORKSPACE}/payara6/glassfish#g" ${TS_HOME}/build.properties
sed -i "s#report.dir=.*#report.dir=${REPORT}#g" ${TS_HOME}/build.properties
sed -i "s#admin.user=.*#admin.user=admin#g" ${TS_HOME}/build.properties
sed -i "s#jersey-bean-validator.*#jakarta.validation-api.jar\${aix.jars}\"/>#g" ${TS_HOME}/build.xml

#Run Tests
cd ${TS_HOME}
ant sigtest
ant test

which mvn
mvn -version

GROUP_ID=jakarta.validation
ARTIFACT_ID=beanvalidation-tck-tests 
BEANVALIDATION_TCK_DIST=beanvalidation-tck-dist

cp ${WORKSPACE}/${BEANVALIDATION_TCK_DIST}-${BV_TCK_VERSION}/artifacts/tck-tests.xml \
	${WORKSPACE}/${BEANVALIDATION_TCK_DIST}-${BV_TCK_VERSION}/artifacts/beanvalidation-tck-tests-${BV_TCK_VERSION}-tck-tests.xml

mvn --global-settings "${PORTING}/settings.xml" org.apache.maven.plugins:maven-install-plugin:3.0.0-M1:install-file \
-Dfile=${WORKSPACE}/${BEANVALIDATION_TCK_DIST}-${BV_TCK_VERSION}/src/pom.xml \
-DgroupId=${GROUP_ID} \
-DartifactId=beanvalidation-tck-parent \
-Dversion=${BV_TCK_VERSION} \
-Dpackaging=pom

mvn --global-settings "${PORTING}/settings.xml" install:install-file \
-Dfile=${WORKSPACE}/${BEANVALIDATION_TCK_DIST}-${BV_TCK_VERSION}/artifacts/beanvalidation-tck-tests-${BV_TCK_VERSION}.jar \
-DgroupId=${GROUP_ID} \
-DartifactId=${ARTIFACT_ID} \
-Dversion=${BV_TCK_VERSION} \
-Dpackaging=jar

mvn --global-settings "${PORTING}/settings.xml" install:install-file \
-Dfile=${WORKSPACE}/${BEANVALIDATION_TCK_DIST}-${BV_TCK_VERSION}/artifacts/beanvalidation-tck-tests-${BV_TCK_VERSION}-tck-tests.xml \
-DgroupId=${GROUP_ID} \
-DartifactId=${ARTIFACT_ID} \
-Dversion=${BV_TCK_VERSION} \
-Dpackaging=xml


#List dependencies used for testing
cd ${TS_HOME}/glassfish-tck-runner
mvn --global-settings "${PORTING}/settings.xml" test

#Generate Reports
echo "<pre>" > ${REPORT}/beanvalidation-$VER-sig/report.html
cat $REPORT/bv_sig_test_results.txt >> $REPORT/beanvalidation-$VER-sig/report.html
echo "</pre>" >> $REPORT/beanvalidation-$VER-sig/report.html
cp $REPORT/beanvalidation-$VER-sig/report.html $REPORT/beanvalidation-$VER-sig/index.html

cp -R ${TS_HOME}/glassfish-tck-runner/target/surefire-reports/* ${REPORT}/beanvalidation-${VER}
if [ -f ${REPORT}/beanvalidation-$VER/test-report.html ]; then
  cp ${REPORT}/beanvalidation-$VER/test-report.html ${REPORT}/beanvalidation-${VER}/report.html
fi

#Copy surefire reports to report directory
mv ${REPORT}/beanvalidation-$VER/TEST-TestSuite.xml  ${REPORT}/beanvalidation-$VER/beanvalidation-$VER-junit-report.xml
sed -i 's/name=\"TestSuite\"/name="beanvalidation-2.0"/g' ${REPORT}/beanvalidation-$VER/beanvalidation-$VER-junit-report.xml

# Create Junit formated file for sigtests
echo '<?xml version="1.0" encoding="UTF-8" ?>' > $REPORT/beanvalidation-$VER-sig/beanvalidation-$VER-sig-junit-report.xml
echo '<testsuite tests="TOTAL" failures="FAILED" name="beanvalidation-3.0.0-sig" time="0.2" errors="0" skipped="0">' >> $REPORT/beanvalidation-$VER-sig/beanvalidation-$VER-sig-junit-report.xml
echo '<testcase classname="BVSigTest" name="beanvalidation" time="0.2">' >> $REPORT/beanvalidation-$VER-sig/beanvalidation-$VER-sig-junit-report.xml
echo '  <system-out>' >> $REPORT/beanvalidation-$VER-sig/beanvalidation-$VER-sig-junit-report.xml
cat $REPORT/bv_sig_test_results.txt >> $REPORT/beanvalidation-$VER-sig/beanvalidation-$VER-sig-junit-report.xml
echo '  </system-out>' >> $REPORT/beanvalidation-$VER-sig/beanvalidation-$VER-sig-junit-report.xml
echo '</testcase>' >> $REPORT/beanvalidation-$VER-sig/beanvalidation-$VER-sig-junit-report.xml
echo '</testsuite>' >> $REPORT/beanvalidation-$VER-sig/beanvalidation-$VER-sig-junit-report.xml

# Fill appropriate test counts
if [ -f "$REPORT/beanvalidation-$VER-sig/report.html" ]; then
  if grep -q STATUS:Passed "$REPORT/beanvalidation-$VER-sig/report.html"; then
    sed -i 's/tests=\"TOTAL\"/tests="1"/g' $REPORT/beanvalidation-$VER-sig/beanvalidation-$VER-sig-junit-report.xml
    sed -i 's/failures=\"FAILED\"/failures="0"/g' $REPORT/beanvalidation-$VER-sig/beanvalidation-$VER-sig-junit-report.xml
  else
    sed -i 's/tests=\"TOTAL\"/tests="1"/g' $REPORT/beanvalidation-$VER-sig/beanvalidation-$VER-sig-junit-report.xml
    sed -i 's/failures=\"FAILED\"/failures="1"/g' $REPORT/beanvalidation-$VER-sig/beanvalidation-$VER-sig-junit-report.xml
  fi
fi

tar zcvf ${WORKSPACE}/bvtck-results.tar.gz ${REPORT} ${WORKSPACE}/bv-tck-glassfish-porting/glassfish-tck-runner/target/surefire-reports ${WORKSPACE}/glassfish5/glassfish/domains/domain1/config ${WORKSPACE}/glassfish5/glassfish/domains/domain1/logs
