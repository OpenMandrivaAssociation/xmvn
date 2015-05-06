#!/bin/bash -ex

resultdir="/var/lib/mock/xmvn-rawhide/result"

# create directories
repo=RPM/latest/
[[ ! -d ${repo} ]] && mkdir -p ${repo}

# update version and release tag in spec file
version=$(sed -n '/<version>/{s/.*>\(.*\)<.*/\1/;s/-SNAPSHOT$//;p;q}' pom.xml)
release=$(git describe --match="[^(jenkins)].*" --tags | sed 's/[^-]*-/0./;s/-/./;s/g/git/')
sed -i "s/^Version:\s\+[0-9.]*$/Version: ${version}/" xmvn.spec
sed -i "s/^Release:\s\+[0-9.]*%{?dist}$/Release: ${release}/" xmvn.spec

# Skip patch application on Jenkins - it is supposed to always use the
# latest vanilla upstream snapshot.
sed -i "/^Patch[0-9]*:/d" xmvn.spec
sed -i "/^%patch[0-9]* -p/d" xmvn.spec

# make tarball
git archive -v --prefix=xmvn-${version}/ HEAD | xz > xmvn-${version}.tar.xz

# crate srpm
rm -f SRPMS/*
rpmbuild -bs --clean --define "_topdir `pwd`" --define "_sourcedir `pwd`" xmvn.spec

# build RPM with custom mock config
rm -Rf ${resultdir}/*
# print root.log and build.log in case of failure
trap "cat ${resultdir}/{root,build}.log || :" 0
mock -r ../..$PWD/fedora-rawhide-x86_64 SRPMS/*.src.rpm

# remove unneeded stuff
rm -f xmvn-*.tar.xz

last_bn=`grep "Build number" ${repo}/info.log | awk '{ print $3 }'`
if [ -n "${last_bn}" ]; then
    mkdir -p RPM/${last_bn}
    mv ${repo}/* RPM/${last_bn}

    # we only want keep RPMs from last 10 builds
    blist=`find ./RPM/ -maxdepth 1 -name "[0-9]*"`
    for bn in $blist; do
        if [ `basename $bn` -lt `expr $last_bn - 10` ]; then
            rm -Rf $bn
        fi
    done
fi

# copy resulting RPMs to RPM/latest
cp ${resultdir}/* ${repo}

tail -n 50 ${resultdir}/build.log

createrepo ${repo}

# store current build number into the file
echo "Build number: $BUILD_NUMBER" >> ${repo}/info.log

