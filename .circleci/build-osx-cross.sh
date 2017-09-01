#!/bin/bash
cd /tmp
git clone https://github.com/tpoechtrager/osxcross.git
cd osxcross
curl -#L https://github.com/phracker/MacOSX-SDKs/releases/download/10.13/MacOSX10.11.sdk.tar.xz -o tarballs/MacOSX10.11.sdk.tar.xz
UNATTENDED=1 OSX_VERSION_MIN=10.8 ./build.sh