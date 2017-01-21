#!/usr/bin/env bash

# This build script will any binaries that the laptop script needs
# and places them inside the releases folder.
# The binaries will only be targeted to Mac OS X (64-bit)
# After the binaries are compiled, you will need to put them in
# a GitHub Release for them to be publiclly accessible.
set -e

LIBGITVER="0.25.0"
RELEASE_PATH=$(pwd)/releases

function compile_libgit() {
  rm -rf "$RELEASE_PATH/libgit2"
  rm -rf libgit2-${LIBGITVER}
  if [ ! -f libgit2-${LIBGITVER}.tar.gz ]; then
    curl -L -o libgit2-${LIBGITVER}.tar.gz https://github.com/libgit2/libgit2/archive/v${LIBGITVER}.tar.gz
  fi
  tar -xzf libgit2-${LIBGITVER}.tar.gz
  mkdir -p libgit2-${LIBGITVER}/build
  (cd libgit2-${LIBGITVER}/build \
    && cmake -DTHREADSAFE=ON \
        -DBUILD_CLAR=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_C_FLAGS=-fPIC \
        -DCMAKE_INSTALL_PREFIX="$RELEASE_PATH/libgit2" .. \
    && cmake --build . --target install)
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
  export PKG_CONFIG_PATH=${RELEASE_PATH}/libgit2/lib/pkgconfig:${PKG_CONFIG_PATH}
  export LIBGIT_PCFILE="${RELEASE_PATH}/libgit2/lib/pkgconfig/libgit2.pc"
  FLAGS=$(pkg-config --static --libs "$LIBGIT_PCFILE") || exit 1
  export CGO_LDFLAGS="${RELEASE_PATH}/libgit2/lib/libgit2.a -L${RELEASE_PATH}/libgit2/lib ${FLAGS}"
  export CGO_CFLAGS="-I${RELEASE_PATH}/libgit2/include"
  BINARY="$RELEASE_PATH/git-seekret-$SUFFIX"
  go build -tags static -ldflags "-linkmode external -extldflags '${CGO_LDFLAGS}'" -o "$BINARY"
  echo
  echo "Build complete. Release binary: $BINARY"
  echo
}

rm -rf "$RELEASE_PATH"
mkdir -p "$RELEASE_PATH"

compile_git_seekrets
