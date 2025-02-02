#!/usr/bin/env bash

SKIP_RC=0
BATCH_INSTALL=0

THIS_DIR=$(cd $(dirname $0); pwd)
if [[ "$THIS_DIR" == *" "* ]]; then
    echo "$THIS_DIR: Torch cannot install to a path containing whitespace.
Please try a different path, one without any spaces."
    exit 1
fi
PREFIX=${PREFIX:-"/usr/local"}
TORCH_LUA_VERSION=${TORCH_LUA_VERSION:-"LUAJIT21"} # by default install LUAJIT21

while getopts 'bsh' x; do
    case "$x" in
        h)
            echo "usage: $0
This script will install Torch and related, useful packages into $PREFIX.

    -b      Run without requesting any user input (will automatically add PATH to shell profile)
    -s      Skip adding the PATH to shell profile
"
            exit 2
            ;;
        b)
            BATCH_INSTALL=1
            ;;
        s)
            SKIP_RC=1
            ;;
    esac
done


# Scrub an anaconda/conda install, if exists, from the PATH.
# It has a malformed MKL library (as of 1/17/2015)
OLDPATH=$PATH
if [[ $(echo $PATH | grep conda) ]]; then
    export PATH=$(echo $PATH | tr ':' '\n' | grep -v "conda[2-9]\?" | uniq | tr '\n' ':')
fi

echo "Prefix set to $PREFIX"

if [[ `uname` == 'Linux' ]]; then
    export CMAKE_LIBRARY_PATH=$PREFIX/include:/opt/OpenBLAS/include:$PREFIX/lib:/opt/OpenBLAS/lib:$CMAKE_LIBRARY_PATH
fi
export CMAKE_PREFIX_PATH=$PREFIX

git submodule update --init --recursive

# If we're on OS X, use clang
if [[ `uname` == "Darwin" ]]; then
    # make sure that we build with Clang. CUDA's compiler nvcc
    # does not play nice with any recent GCC version.
    export CC=clang
    export CXX=clang++
fi
# If we're on Arch linux, use gcc v5
if [[ `uname -a` == *"ARCH"* ]]; then
    path_to_gcc5=$(which gcc-5)
    if [ -x "$path_to_gcc5" ]; then
      export CC="$path_to_gcc5"
    else
      echo "Warning: GCC v5 not found. CUDA v8 is incompatible with GCC v6, if installation fails, consider running \$ pacman -S gcc5"
    fi
fi

echo "Installing Lua version: ${TORCH_LUA_VERSION}"
git clone https://luajit.org/git/luajit.git
cd luajit
make && make install
ln -sf luajit-2.1.0-beta3 /usr/local/bin/luajit
cd ..
apt-get install luarocks -y

#mkdir -p install
#mkdir -p build
#cd build
#cmake .. -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DCMAKE_BUILD_TYPE=Release -DWITH_${TORCH_LUA_VERSION}=ON 2>&1 >>$PREFIX/install.log || exit 1
#(make 2>&1 >>$PREFIX/install.log  || exit 1) && (make install 2>&1 >>$PREFIX/install.log || exit 1)
#cd ..

# Check for a CUDA install (using nvcc instead of nvidia-smi for cross-platform compatibility)
path_to_nvcc=$(which nvcc)
if [ $? == 1 ]; then { # look for it in /usr/local
  if [[ -f /usr/local/cuda/bin/nvcc ]]; then {
    path_to_nvcc=/usr/local/cuda/bin/nvcc
  } 
  elif [[ -f /opt/cuda/bin/nvcc ]]; then { # default path for arch
    path_to_nvcc=/opt/cuda/bin/nvcc
  } fi
} fi

# check if we are on mac and fix RPATH for local install
path_to_install_name_tool=$(which install_name_tool 2>/dev/null)
if [ -x "$path_to_install_name_tool" ]
then
   if [ ${TORCH_LUA_VERSION} == "LUAJIT21" ] || [ ${TORCH_LUA_VERSION} == "LUAJIT20" ] ; then
       install_name_tool -id ${PREFIX}/lib/libluajit.dylib ${PREFIX}/lib/libluajit.dylib
   else
       install_name_tool -id ${PREFIX}/lib/liblua.dylib ${PREFIX}/lib/liblua.dylib
   fi
fi

if [ -x "$path_to_nvcc" ] || [ -x "$path_to_nvidiasmi" ]
then
    echo "Found CUDA on your machine. Installing CMake 3.6 modules to get up-to-date FindCUDA"
    cd ${THIS_DIR}/cmake/3.6 && \
(cmake -E make_directory build && cd build && cmake .. -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        && make install) && echo "FindCuda bits of CMake 3.6 installed" || exit 1
fi

#setup_lua_env_cmd=$($PREFIX/bin/luarocks path)
#eval "$setup_lua_env_cmd"

echo "Installing common Lua packages"
cd ${THIS_DIR}/extra/luafilesystem && luarocks make rockspecs/luafilesystem-1.6.3-1.rockspec || exit 1
cd ${THIS_DIR}/extra/penlight && luarocks make penlight-scm-1.rockspec || exit 1
cd ${THIS_DIR}/extra/lua-cjson && luarocks make lua-cjson-2.1devel-1.rockspec || exit 1

echo "Installing core Torch packages"
cd ${THIS_DIR}/extra/luaffifb && luarocks make luaffi-scm-1.rockspec       || exit 1
cd ${THIS_DIR}/pkg/sundown   && luarocks make rocks/sundown-scm-1.rockspec || exit 1
cd ${THIS_DIR}/pkg/cwrap     && luarocks make rocks/cwrap-scm-1.rockspec   || exit 1
cd ${THIS_DIR}/pkg/paths     && luarocks make rocks/paths-scm-1.rockspec   || exit 1
cd ${THIS_DIR}/pkg/torch     && luarocks make rocks/torch-scm-1.rockspec   || exit 1
cd ${THIS_DIR}/pkg/dok       && luarocks make rocks/dok-scm-1.rockspec     || exit 1
cd ${THIS_DIR}/exe/trepl     && luarocks make trepl-scm-1.rockspec         || exit 1
cd ${THIS_DIR}/pkg/sys       && luarocks make sys-1.1-0.rockspec           || exit 1
cd ${THIS_DIR}/pkg/xlua      && luarocks make xlua-1.0-0.rockspec          || exit 1
cd ${THIS_DIR}/extra/moses   && luarocks make rockspec/moses-1.6.1-1.rockspec || exit 1
cd ${THIS_DIR}/extra/nn      && luarocks make rocks/nn-scm-1.rockspec      || exit 1
cd ${THIS_DIR}/extra/graph   && luarocks make rocks/graph-scm-1.rockspec   || exit 1
cd ${THIS_DIR}/extra/nngraph && luarocks make nngraph-scm-1.rockspec       || exit 1
cd ${THIS_DIR}/pkg/image     && luarocks make image-1.1.alpha-0.rockspec   || exit 1
cd ${THIS_DIR}/pkg/optim     && luarocks make optim-1.0.5-0.rockspec       || exit 1

if [ -x "$path_to_nvcc" ]
then
    echo "Found CUDA on your machine. Installing CUDA packages"
    cd ${THIS_DIR}/extra/cutorch && luarocks make rocks/cutorch-scm-1.rockspec || exit 1
    cd ${THIS_DIR}/extra/cunn    && luarocks make rocks/cunn-scm-1.rockspec    || exit 1
fi

# Optional packages
echo "Installing optional Torch packages"
cd ${THIS_DIR}/pkg/gnuplot          && luarocks make rocks/gnuplot-scm-1.rockspec
cd ${THIS_DIR}/exe/env              && luarocks make env-scm-1.rockspec
cd ${THIS_DIR}/extra/nnx            && luarocks make nnx-0.1-1.rockspec
cd ${THIS_DIR}/exe/qtlua            && luarocks make rocks/qtlua-scm-1.rockspec
cd ${THIS_DIR}/pkg/qttorch          && luarocks make rocks/qttorch-scm-1.rockspec
cd ${THIS_DIR}/extra/threads        && luarocks make rocks/threads-scm-1.rockspec
cd ${THIS_DIR}/extra/argcheck       && luarocks make rocks/argcheck-scm-1.rockspec

# Optional CUDA packages
if [ -x "$path_to_nvcc" ]
then
    echo "Found CUDA on your machine. Installing optional CUDA packages"
    cd ${THIS_DIR}/extra/cudnn   && luarocks make cudnn-scm-1.rockspec
fi
