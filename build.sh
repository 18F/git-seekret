#!/usr/bin/env bash

# This build script will any binaries that the laptop script needs
# and places them inside the releases folder.
# The binaries will only be targeted to Mac OS X (64-bit)
# After the binaries are compiled, you will need to put them in
# a GitHub Release for them to be publiclly accessible.
set -e

LIBGITVER="0.25.1"
LIBSSHVER="1.8.0"
LIBCURLVER="7.54.0"
OPENSSLVER="1.0.2k"

RELEASE_PATH=$(pwd)/releases
BIN_RELEASE_PATH=$(pwd)/dist

function compile_openssl() {
  rm -rf openssl-${OPENSSLVER}
  if [ ! -f openssl-${OPENSSLVER}.tar.gz ]; then
    curl --progress-bar -L -o openssl-${OPENSSLVER}.tar.gz https://www.openssl.org/source/openssl-${OPENSSLVER}.tar.gz
  fi
  tar -xzf openssl-${OPENSSLVER}.tar.gz
  pushd openssl-${OPENSSLVER}
  ./Configure "$OPENSSL_TARGET" no-shared no-ssl2 no-ssl3 no-zlib --prefix="${RELEASE_PATH}/openssl" --openssldir="${RELEASE_PATH}/openssl"
  make depend && make
  make install
  popd
}

function compile_libssh() {
  compile_openssl

  rm -rf libssh2-${LIBSSHVER}

  if [ ! -f libssh2-${LIBSSHVER}.tar.gz ]; then
    curl --progress-bar -L -o libssh2-${LIBSSHVER}.tar.gz https://www.libssh2.org/download/libssh2-${LIBSSHVER}.tar.gz
  fi
  tar -xzf libssh2-${LIBSSHVER}.tar.gz
  pushd libssh2-${LIBSSHVER}
  export PKG_CONFIG_PATH="${RELEASE_PATH}/openssl/lib/pkgconfig:${PKG_CONFIG_PATH}"
  export LIBSSL_PCFILE="${RELEASE_PATH}/openssl/lib/pkgconfig/libssl.pc"
  export LIBCRYPTO_PCFILE="${RELEASE_PATH}/openssl/lib/pkgconfig/libcrypto.pc"
  LIBSSL_CFLAGS=$(pkg-config --static --cflags "$LIBSSL_PCFILE") || exit 1
  LIBCRYPTO_CFLAGS=$(pkg-config --static --cflags "$LIBCRYPTO_PCFILE") || exit 1
  LIBSSL_LDFLAGS=$(pkg-config --static --libs-only-L "$LIBSSL_PCFILE") || exit 1
  LIBCRYPTO_LDFLAGS=$(pkg-config --static --libs-only-L "$LIBCRYPTO_PCFILE") || exit 1
  LIBSSL_LIBS=$(pkg-config --static --libs-only-l --libs-only-other "$LIBSSL_PCFILE") || exit 1
  LIBCRYPTO_LIBS=$(pkg-config --static --libs-only-l --libs-only-other "$LIBCRYPTO_PCFILE") || exit 1
  export LDFLAGS="${LIBSSL_LDFLAGS} ${LIBCRYPTO_LDFLAGS} ${LDFLAGS}"
  export CFLAGS="${LIBSSL_CFLAGS} ${LIBCRYPTO_CFLAGS} ${CFLAGS}"
  export LIBS="${LIBSSL_LIBS} ${LIBCRYPTO_LIBS} ${LIBS}"
  ./configure --target="$HOSTCONFIG" --build="$BUILDCONFIG" --host="$HOSTCONFIG" --disable-examples-build --disable-shared --with-libssl-prefix="${RELEASE_PATH}/openssl" --prefix="${RELEASE_PATH}/libssh2"
  make && make install
  popd
}

function compile_libcurl() {
  compile_libssh

  rm -rf curl-${LIBCURLVER}
  if [ ! -f curl-${LIBCURLVER}.tar.gz ]; then
    curl --progress-bar -L -o curl-${LIBCURLVER}.tar.gz https://curl.haxx.se/download/curl-${LIBCURLVER}.tar.gz
  fi
  tar -xzf curl-${LIBCURLVER}.tar.gz
  pushd curl-${LIBCURLVER}
  export PKG_CONFIG_PATH="${RELEASE_PATH}/libssh2/lib/pkgconfig:${PKG_CONFIG_PATH}"
  export LIBSSH2_PCFILE="${RELEASE_PATH}/libssh2/lib/pkgconfig/libssh2.pc"
  LIBSSH2_CFLAGS=$(pkg-config --static --cflags "${LIBSSH2_PCFILE}") || exit 1
  LIBSSH2_LDFLAGS=$(pkg-config --static --libs-only-L "${LIBSSH2_PCFILE}") || exit 1
  LIBSSH2_LIBS=$(pkg-config --static --libs-only-l --libs-only-other "${LIBSSH2_PCFILE}") || exit 1
  export LDFLAGS="${LIBSSH2_LDFLAGS} ${LDFLAGS}"
  export CFLAGS="${LIBSSH2_CFLAGS} ${CFLAGS}"
  export LIBS="${LIBSSH2_LIBS} ${LIBS}"
  ./configure --target="$HOSTCONFIG" --build="$BUILDCONFIG" --host="$HOSTCONFIG" --with-ssl="${RELEASE_PATH}/openssl" --with-libssh2="${RELEASE_PATH}/libssh2" --without-librtmp --disable-ldap --disable-shared --prefix="${RELEASE_PATH}/curl"
  make && make install
  popd
}

function compile_libgit() {
  compile_libcurl

  rm -rf "$RELEASE_PATH/libgit2"
  rm -rf libgit2-${LIBGITVER}
  if [ ! -f libgit2-${LIBGITVER}.tar.gz ]; then
    curl --progress-bar -L -o libgit2-${LIBGITVER}.tar.gz https://github.com/libgit2/libgit2/archive/v${LIBGITVER}.tar.gz
  fi
  tar -xzf libgit2-${LIBGITVER}.tar.gz
  mkdir -p libgit2-${LIBGITVER}/build
  export PKG_CONFIG_PATH="${RELEASE_PATH}/curl/lib/pkgconfig:${PKG_CONFIG_PATH}"
  export LIBCURL_PCFILE="${RELEASE_PATH}/curl/lib/pkgconfig/libcurl.pc"
  pushd libgit2-${LIBGITVER}/build
  cmake -DCMAKE_SYSTEM_NAME="$CMAKE_SYSTEM_NAME" \
        -DCMAKE_C_COMPILER="${CC:-gcc}" \
        -DTHREADSAFE=ON \
        -DBUILD_CLAR=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_C_FLAGS="-fPIC ${CFLAGS}"\
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

  if [ -z "$GOPATH" ]; then
    export GOPATH=/go
  fi

  # build it
  case $OSTYPE in
    linux*)
      export GOOS=linux
      export HOSTCONFIG=x86_64-unknown-linux-gnu
      export BUILDCONFIG="$HOSTCONFIG"
      export OPENSSL_TARGET="linux-x86_64"
      export CMAKE_SYSTEM_NAME=Linux
      SUFFIX=linux
      ;;
    darwin*)
      export GOOS=darwin
      export HOSTCONFIG=x86_64-apple-darwin15
      export BUILDCONFIG="$HOSTCONFIG"
      export OPENSSL_TARGET="darwin64-x86_64-cc"
      export CMAKE_SYSTEM_NAME=Darwin
      SUFFIX=osx
      if [ -n "$CROSS_DIR" ]; then
        export CC="$HOSTCONFIG-clang"
        export CXX="$HOSTCONFIG-clang++"
        export MAKEDEPPROG="$CC"
        export AR="${HOSTCONFIG}-ar"
        export AS="${HOSTCONFIG}-as"
        export LD="${HOSTCONFIG}-ld"
        export LIBTOOL="${HOSTCONFIG}-libtool"
        export RANLIB="${HOSTCONFIG}-ranlib"
        export NM="${HOSTCONFIG}-nm"
        export BUILDCONFIG=x86_64-unknown-linux-gnu
      fi
      ;;
    *)
      echo "unknown platform: $OSTYPE"
      echo "Trying to build anyway"
      SUFFIX=$OSTYPE
      ;;
  esac

  compile_libgit

  if which glide > /dev/null; then
    echo "Found glide"
  else
    echo "glide does not exist. Installing..."
    (curl --progress-bar https://glide.sh/get | sh)
  fi
  rm -rf vendor
  glide install
  ln -sf "$(pwd)/libgit2-${LIBGITVER}/build" "${GOPATH}/src/github.com/18F/git-seekret/vendor/github.com/libgit2/git2go/vendor/libgit2/build"

  export GOARCH=amd64
  export PKG_CONFIG_PATH="${RELEASE_PATH}/libgit2/lib/pkgconfig:${PKG_CONFIG_PATH}"
  export LIBGIT_PCFILE="${RELEASE_PATH}/libgit2/lib/pkgconfig/libgit2.pc"
  LIBGIT_LDFLAGS=$(pkg-config --static --libs-only-L "$LIBGIT_PCFILE") || exit 1
  LIBGIT_LIBS=$(pkg-config --static --libs-only-l --libs-only-other "$LIBGIT_PCFILE") || exit 1
  export CGO_ENABLED=1
  export CGO_LDFLAGS="$LDFLAGS $LIBS $LIBGIT_LDFLAGS $LIBGIT_LIBS"
  export CGO_CFLAGS="$CFLAGS"
  export BINARY="$BIN_RELEASE_PATH/git-seekret-$SUFFIX"
  go build -tags static -ldflags "-linkmode external -extldflags '${CGO_LDFLAGS}'" -o "$BINARY"
  echo
  echo "Build complete. Release binary: $BINARY"
  echo
}

function test_git_seekrets() {
  echo
  if [ -z "$CROSS_DIR" ]; then
    echo "Trying to run git-seekret.."
    "$BINARY" || exit 1
    echo
  else
    echo "Compiled binary type:"
    file "$BINARY" || exit 1
  fi
  echo "Running tests.."
  go test -tags static "$(glide nv)"
  echo
  echo "..All Done"
}

rm -rf "$RELEASE_PATH" "$BIN_RELEASE_PATH"
mkdir -p "$RELEASE_PATH"
mkdir -p "$BIN_RELEASE_PATH"

compile_git_seekrets
test_git_seekrets
