#!/bin/bash

# This build script will any binaries that the laptop script needs
# and places them inside the releases folder.
# The binaries will only be targeted to Mac OS X (64-bit)
# After the binaries are compiled, you will need to put them in
# a GitHub Release for them to be publiclly accessible.
set -e

LIBGITVER="0.24.0"
LIBSSHVER="1.8.0"
BIN_PATH=$(pwd)/releases

function compile_libssh_osx() {
  if [ ! -d /usr/local/opt/curl ]; then
    brew install curl
  else
    brew upgrade curl || true
  fi
  if [ ! -d /usr/local/opt/openssl ]; then
    brew install openssl
  else
    brew upgrade openssl || true
  fi
  if [ ! -f libssh2-${LIBSSHVER}.tar.gz ]; then
    wget -O libssh2-${LIBSSHVER}.tar.gz https://www.libssh2.org/download/libssh2-${LIBSSHVER}.tar.gz
  fi
  tar -xzf libssh2-${LIBSSHVER}.tar.gz
  pushd libssh2-${LIBSSHVER}
  export PKG_CONFIG_PATH="/usr/local/opt/curl/lib/pkgconfig:/usr/local/opt/openssl/lib/pkgconfig"
  export CURL_PCFILE=/usr/local/opt/curl/lib/pkgconfig/libcurl.pc
  export SSL_PCFILE=/usr/local/opt/openssl/lib/pkgconfig/libssl.pc
  export CRYPTO_PCFILE=/usr/local/opt/openssl/lib/pkgconfig/libcrypto.pc
  CURL_FLAGS=$(pkg-config --static --libs "$CURL_PCFILE") || exit 1
  SSL_FLAGS=$(pkg-config --static --libs "$SSL_PCFILE") || exit 1
  CRYPTO_FLAGS=$(pkg-config --static --libs "$CRYPTO_PCFILE") || exit 1
  LDFLAGS="-mmacosx-version-min=10.10 -w -arch x86_64 $CURL_FLAGS $SSL_FLAGS $CRYPTO_FLAGS" \
    CPPFLAGS="-I/usr/local/opt/curl/include -I/usr/local/opt/openssl/include" \
    ./configure --disable-shared --prefix="$BIN_PATH/libssh2"
  make && make install
  popd
  rm -rf libssh2-${LIBSSHVER}
}

function compile_libgit_osx() {
  compile_libssh_osx
  if [ ! -f libgit2-${LIBGITVER}.tar.gz ]; then
    wget -O libgit2-${LIBGITVER}.tar.gz https://github.com/libgit2/libgit2/archive/v${LIBGITVER}.tar.gz
  fi
  tar -xzf libgit2-${LIBGITVER}.tar.gz
  mkdir -p libgit2-${LIBGITVER}/build
  pushd libgit2-${LIBGITVER}/build
  export PKG_CONFIG_PATH=${BIN_PATH}/libssh2/lib/pkgconfig:${PKG_CONFIG_PATH}
  export SSH_PCFILE=$BIN_PATH/libssh2/lib/pkgconfig/libssh2.pc
  SSH_FLAGS=$(pkg-config --static --libs "$SSH_PCFILE") || exit 1
  cmake -DTHREADSAFE=ON \
      -DBUILD_CLAR=OFF \
      -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_C_FLAGS=-fPIC \
      -DCMAKE_INSTALL_PREFIX="$BIN_PATH/libgit2" ..
  LDFLAGS="-mmacosx-version-min=10.10 -w -arch x86_64 $SSH_FLAGS" \
      CPPFLAGS="-I$BIN_PATH/libssh2/include" \
      cmake --build . --target install
  popd
  rm -rf libgit2-${LIBGITVER}
}

function compile_git_seekrets_Darwin() {
  compile_libgit_osx
  if which go > /dev/null; then
    echo "Found Go toolchain"
    brew upgrade go || true
  else
   brew install go
  fi
  if which glide > /dev/null; then
    echo "Found glide"
    brew upgrade glide || true
  else
    echo "Glide does not exist. Run 'brew install glide'"
    brew install glide
  fi
  rm -rf vendor
  glide install
  # build it
  export GOOS=darwin
  export GOARCH=amd64
  export PKG_CONFIG_PATH=${BIN_PATH}/libgit2/lib/pkgconfig:${PKG_CONFIG_PATH}
  export LIBGIT_PCFILE="${BIN_PATH}/libgit2/lib/pkgconfig/libgit2.pc"

  FLAGS=$(pkg-config --static --libs "$LIBGIT_PCFILE") || exit 1
  export CGO_LDFLAGS="${BIN_PATH}/libgit2/lib/libgit2.a -L${BIN_PATH}/libssh2/lib ${BIN_PATH}/libssh2/lib/libssh2.a -L${BIN_PATH}/libgit2/lib ${FLAGS} ${SSH_FLAGS}"
  export CGO_CFLAGS="-I${BIN_PATH}/libgit2/include -I${BIN_PATH}/libssh2/include"
  LDFLAGS="-nodefaultlibs -nostdlib $CGO_LDFLAGS"
  go build -ldflags "-linkmode external -extldflags '${LDFLAGS}'" -o git-seekret-osx
  # place the binary in folder
  mv git-seekret-osx "$BIN_PATH"/git-seekret-osx
  # cleanup workspace
  rm -rf "$BIN_PATH/libssh2"
  rm -rf "$BIN_PATH/libgit2"
}

rm -rf "$BIN_PATH"
mkdir -p "$BIN_PATH"

compile_git_seekrets_$(uname -s)
