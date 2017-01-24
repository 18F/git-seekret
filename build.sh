#!/usr/bin/env bash

# This build script will any binaries that the laptop script needs
# and places them inside the releases folder.
# The binaries will only be targeted to Mac OS X (64-bit)
# After the binaries are compiled, you will need to put them in
# a GitHub Release for them to be publiclly accessible.
set -e

LIBGITVER="0.25.1"
LIBSSHVER="1.8.0"
LIBCURLVER="7.52.1"
OPENSSLVER="1.0.2j"

RELEASE_PATH=$(pwd)/releases

function compile_openssl() {
  rm -rf openssl-${OPENSSLVER}
  if [ ! -f openssl-1.0.2j.tar.gz ]; then
    curl -L -o openssl-${OPENSSLVER}.tar.gz https://www.openssl.org/source/openssl-${OPENSSLVER}.tar.gz
  fi
  tar -xvf openssl-${OPENSSLVER}.tar.gz
  pushd openssl-${OPENSSLVER}
  export KERNEL_BITS=64
  ./config no-shared no-ssl2 no-ssl3 --prefix="${RELEASE_PATH}/openssl" --openssldir="${RELEASE_PATH}/openssl"
  make depend && make
  make install
  popd
}

function compile_libssh() {
  compile_openssl

  rm -rf libssh2-${LIBSSHVER}

  if [ ! -f libssh2-${LIBSSHVER}.tar.gz ]; then
    curl -L -o libssh2-${LIBSSHVER}.tar.gz https://www.libssh2.org/download/libssh2-${LIBSSHVER}.tar.gz
  fi
  tar -xzf libssh2-${LIBSSHVER}.tar.gz
  pushd libssh2-${LIBSSHVER}
  export PKG_CONFIG_PATH="${RELEASE_PATH}/openssl/lib/pkgconfig:${PKG_CONFIG_PATH}"
  export LIBSSL_PCFILE="${RELEASE_PATH}/openssl/lib/pkgconfig/libssl.pc"
  export LIBCRYPTO_PCFILE="${RELEASE_PATH}/openssl/lib/pkgconfig/libcrypto.pc"
  ./configure --disable-shared --with-libssl-prefix="${RELEASE_PATH}/openssl" --prefix="${RELEASE_PATH}/libssh2"
  make && make install
  popd
}

function compile_libcurl() {
  compile_libssh

  rm -rf curl-${LIBCURLVER}
  if [ ! -f curl-${LIBCURLVER}.tar.gz ]; then
    curl -L -o curl-${LIBCURLVER}.tar.gz https://curl.haxx.se/download/curl-${LIBCURLVER}.tar.gz
  fi
  tar -xvf curl-${LIBCURLVER}.tar.gz
  pushd curl-${LIBCURLVER}
  export PKG_CONFIG_PATH="${RELEASE_PATH}/libssh2/lib/pkgconfig:${PKG_CONFIG_PATH}"
  export LIBSSH2_PCFILE="${RELEASE_PATH}/libssh2/lib/pkgconfig/libssh2.pc"
  ./configure --with-ssl="${RELEASE_PATH}/openssl" --with-libssh2="${RELEASE_PATH}/libssh2" --without-librtmp --disable-ldap --disable-shared --prefix="${RELEASE_PATH}/curl"
  make && make install
  popd
}

function compile_libgit() {
  compile_libcurl

  rm -rf "$RELEASE_PATH/libgit2"
  rm -rf libgit2-${LIBGITVER}
  if [ ! -f libgit2-${LIBGITVER}.tar.gz ]; then
    curl -L -o libgit2-${LIBGITVER}.tar.gz https://github.com/libgit2/libgit2/archive/v${LIBGITVER}.tar.gz
  fi
  tar -xzf libgit2-${LIBGITVER}.tar.gz
  mkdir -p libgit2-${LIBGITVER}/build
  export PKG_CONFIG_PATH="${RELEASE_PATH}/curl/lib/pkgconfig:${PKG_CONFIG_PATH}"
  export LIBCURL_PCFILE="${RELEASE_PATH}/curl/lib/pkgconfig/libcurl.pc"
  pushd libgit2-${LIBGITVER}/build
  cmake -DTHREADSAFE=ON \
        -DBUILD_CLAR=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_C_FLAGS=-fPIC \
        -DCMAKE_INSTALL_PREFIX="$RELEASE_PATH/libgit2" ..
  cmake --build . --target install
  popd
}

function compile_git_seekrets() {

  if which go > /dev/null; then
    echo "Found Go toolchain"
  else
    echo "Go toolchain does not exist."
    if [ "x$OS" == "xdarwin" ]; then
      brew install go
    else
      echo "Please install golang from your package manager or from https://golang.org/dl/"
      exit 1
    fi
  fi

  compile_libgit

  if which glide > /dev/null; then
    echo "Found glide"
  else
    echo "glide does not exist. Installing..."
    (curl https://glide.sh/get | sh)
  fi
  rm -rf vendor
  glide install
  ln -sf "$(pwd)/libgit2-${LIBGITVER}/build" "${GOPATH}/src/github.com/18F/git-seekret/vendor/github.com/libgit2/git2go/vendor/libgit2/build"

  # build it
  case $OSTYPE in
    linux*)
      export GOOS=linux
      SUFFIX=linux
      ;;
    darwin*)
      export GOOS=darwin
      SUFFIX=osx
      ;;
    *)
      echo "unknown platform: $OSTYPE"
      echo "Trying to build anyway"
      SUFFIX=$OSTYPE
      ;;
  esac

  export GOARCH=amd64
  export PKG_CONFIG_PATH="${RELEASE_PATH}/libgit2/lib/pkgconfig:${PKG_CONFIG_PATH}"
  export LIBGIT_PCFILE="${RELEASE_PATH}/libgit2/lib/pkgconfig/libgit2.pc"
  LIBGIT_FLAGS=$(pkg-config --static --libs "$LIBGIT_PCFILE") || exit 1
  LIBCURL_FLAGS=$(pkg-config --static --libs "$LIBCURL_PCFILE") || exit 1
  LIBSSL_FLAGS=$(pkg-config --static --libs "$LIBSSL_PCFILE") || exit 1
  LIBCRYPTO_FLAGS=$(pkg-config --static --libs "$LIBCRYPTO_PCFILE") || exit 1
  LIBSSH2_FLAGS=$(pkg-config --static --libs "$LIBSSH2_PCFILE") || exit 1
  export CGO_LDFLAGS="$LIBGIT_FLAGS $LIBCURL_FLAGS $LIBSSL_FLAGS $LIBCRYPTO_FLAGS $LIBSSH2_FLAGS"
  export CGO_CFLAGS="-I${RELEASE_PATH}/libgit2/include -I${RELEASE_PATH}/libssh2/include -I${RELEASE_PATH}/curl/include -I${RELEASE_PATH}/openssl/include"
  BINARY="$RELEASE_PATH/git-seekret-$SUFFIX"
  go build -tags static -ldflags "-linkmode external -extldflags '${CGO_LDFLAGS}'" -o "$BINARY"
  echo
  echo "Build complete. Release binary: $BINARY"
  echo
}

function test_git_seekrets() {
  echo
  echo "Trying to run git-seekret.."
  "${RELEASE_PATH}"/git-seekret-* || exit 1
  echo
  echo "Running tests.."
  go test -tags static "$(glide nv)"
  echo
  echo "..All Done"
}

rm -rf "$RELEASE_PATH"
mkdir -p "$RELEASE_PATH"

compile_git_seekrets
test_git_seekrets