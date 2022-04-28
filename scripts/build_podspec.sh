#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftNIO open source project
##
## Copyright (c) 2017-2019 Apple Inc. and the SwiftNIO project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftNIO project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

set -eu

function usage() {
  echo "$0 [-u] version nio_version"
  echo
  echo "OPTIONS:"
  echo "  -u: Additionally upload the podspec"
}

upload=false
while getopts ":u" opt; do
  case $opt in
    u)
      upload=true
      ;;
    \?)
      usage
      exit 1
      ;;
  esac
done
shift "$((OPTIND-1))"

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

version=$1

# Current SwiftNIO Version to add as dependency in the .podspec
nio_version=$2
if [[ $nio_version =~ ^([0-9]+)\. ]]; then
  # Extract and incremenet the major version to use an upper bound on the
  # version requirement (we can't use '~>' as it means 'up to the next
  # major' if you specify x.y and 'up to the next minor' if you specify x.y.z).
  next_major_version=$((${BASH_REMATCH[1]} + 1))
else
  echo "Invalid NIO version '$nio_version'"
  exit 1
fi

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
tmpdir=$(mktemp -d /tmp/.build_podspecsXXXXXX)
echo "Building podspec in $tmpdir"

# Right now this is only valid because the transitive dependencies of NIOExtras
# and NIOSOCKS are the same.
names=("NIOExtras" "NIOSOCKS")
for name in "${names[@]}"; do
  podname="Swift${name}"
cat > "${tmpdir}/${podname}.podspec" <<- EOF
Pod::Spec.new do |s|
  s.name = '$podname'
  s.version = '$version'
  s.license = { :type => 'Apache 2.0', :file => 'LICENSE.txt' }
  s.summary = 'Useful code around SwiftNIO.'
  s.homepage = 'https://github.com/apple/swift-nio-extras'
  s.author = 'Apple Inc.'
  s.source = { :git => 'https://github.com/apple/swift-nio-extras.git', :tag => s.version.to_s }
  s.documentation_url = 'https://github.com/apple/swift-nio-extras'
  s.module_name = 'NIOExtras'

  s.swift_version = '5.0'
  s.cocoapods_version = '>=1.6.0'
  s.ios.deployment_target = '10.0'
  s.osx.deployment_target = '10.12'
  s.tvos.deployment_target = '10.0'
  s.watchos.deployment_target = '6.0'

  s.dependency 'CNIOAtomics', '>= $nio_version', '< $next_major_version'
  s.dependency 'CNIODarwin', '>= $nio_version', '< $next_major_version'
  s.dependency 'CNIOLinux', '>= $nio_version', '< $next_major_version'
  s.dependency 'CNIOWindows', '>= $nio_version', '< $next_major_version'
  s.dependency 'SwiftNIO', '>= $nio_version', '< $next_major_version'
  s.dependency 'SwiftNIOConcurrencyHelpers', '>= $nio_version', '< $next_major_version'
  s.dependency 'SwiftNIOCore', '>= $nio_version', '< $next_major_version'
  s.dependency 'SwiftNIOEmbedded', '>= $nio_version', '< $next_major_version'
  s.dependency 'SwiftNIOPosix', '>= $nio_version', '< $next_major_version'
  s.dependency '_NIODataStructures', '>= $nio_version', '< $next_major_version'

  s.source_files = 'Sources/$name/**/*.swift'
end
EOF

  if $upload; then
    echo "Uploading ${tmpdir}/${podname}.podspec"
    pod trunk push --synchronous "${tmpdir}/${podname}.podspec"
  else
    echo "Generated podspec available at ${tmpdir}/${podname}.podspec"
  fi
done

