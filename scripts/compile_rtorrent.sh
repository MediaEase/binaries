#!/bin/bash

# Declare global variables specific to rtorrent
declare -g patches_dir
declare -g output_dir
declare -g build_dir
declare -g rtorrentlevel
declare -g rtorrentpipe
declare -g stdc
declare -g app_name="rtorrent"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(dirname "$script_dir")"
export repo_root
# shellcheck disable=SC1091
source "$(dirname "$0")/common_functions.sh"

# Assign values to global variables
patches_dir="$repo_root/patches"

# Include only rtorrent versions
rt_versions=("0.9.6" "0.9.7" "0.9.8")

# Function to set rTorrent version parameters and update output_dir, build_dir, and archive_dir accordingly
function set_rtorrent_version() {
    case $1 in
    '0.9.6' | 096)
        rtorrentver='0.9.6'
        libtorrentver='0.13.6'
        ;;
    '0.9.7' | 097)
        rtorrentver='0.9.7'
        libtorrentver='0.13.7'
        ;;
    '0.9.8' | 098)
        rtorrentver='0.9.8'
        libtorrentver='0.13.8'
        ;;
    *)
        echo "Error: $1 is not a valid rTorrent version"
        exit 1
        ;;
    esac
    build_archive_dir "${app_name}" "${rtorrentver}"
}

# Function to configure rTorrent compilation parameters
function configure_rtorrent() {
    export rtorrentflto
    # Disable LTO for now
    rtorrentflto=""
    memory=$(awk '/MemAvailable/ {printf( "%.f\n", $2 / 1024 )}' /proc/meminfo)
    if [[ $memory -gt 512 ]]; then
        rtorrentpipe="-pipe"
    else
        rtorrentpipe=""
    fi
    if [ "$(nproc)" -le 1 ]; then
        rtorrentlevel="-O1"
    elif [ "$(nproc)" -ge 8 ]; then
        rtorrentlevel="-O3"
    else
        rtorrentlevel="-O2"
    fi
}

# Function to install dependencies specific to rtorrent
install_depends_rtorrent() {
    echo "Installing dependencies for ${app_name}"
    # Install mktorrent
    cd /tmp || exit
    curl -sL https://github.com/Rudde/mktorrent/archive/v1.1.zip -o mktorrent.zip
    rm -rf /tmp/mktorrent
    unzip -q -d mktorrent -j mktorrent.zip >/dev/null
    cd mktorrent || exit
    make >/dev/null
    sudo make install PREFIX=/usr >/dev/null
    cd /tmp || exit
    rm -rf mktorrent*
    echo "Dependencies installed for ${app_name}"
}

# Function to build xmlrpc-c
function build_xmlrpc_c() {
    if [[ ! -d /tmp/xmlrpc-c && ! -f /tmp/xmlrpc-c/config.guess ]]; then
        echo "Building xmlrpc-c"
        rm -rf /tmp/xmlrpc-c /tmp/dist/xmlrpc-c
        svn checkout -q http://svn.code.sf.net/p/xmlrpc-c/code/advanced /tmp/xmlrpc-c >/dev/null 2>&1 || {
            echo "Error checking out xmlrpc-c"
            exit 1
        }
        echo "Patching xmlrpc-c"
        cp "${patches_dir}/xmlrpc/xmlrpc-config.guess" /tmp/xmlrpc-c/config.guess
        cp "${patches_dir}/xmlrpc/xmlrpc-config.sub" /tmp/xmlrpc-c/config.sub
        cd /tmp/xmlrpc-c || exit
        ./configure --prefix=/usr --disable-cplusplus --disable-wininet-client --disable-libwww-client >/dev/null || {
            echo "Error configuring xmlrpc-c"
            exit 1
        }
        XMLRPC_MAJOR_RELEASE=$(awk '/XMLRPC_MAJOR_RELEASE/ {print $3}' /tmp/xmlrpc-c/version.mk)
        XMLRPC_MINOR_RELEASE=$(awk '/XMLRPC_MINOR_RELEASE/ {print $3}' /tmp/xmlrpc-c/version.mk)
        XMLRPC_POINT_RELEASE=$(awk '/XMLRPC_POINT_RELEASE/ {print $3}' /tmp/xmlrpc-c/version.mk)
        VERSION=${XMLRPC_MAJOR_RELEASE}.${XMLRPC_MINOR_RELEASE}.${XMLRPC_POINT_RELEASE}
        echo "xmlrpc-c patched and configured"
        make -j"$(nproc)" CFLAGS="-w ${rtorrentflto} ${rtorrentpipe} ${rtorrentlevel}" >/dev/null || {
            echo "Error building xmlrpc-c"
            exit 1
        }
        make DESTDIR=/tmp/dist/xmlrpc-c install >/dev/null || {
            echo "Error installing xmlrpc-c"
            exit 1
        }
        sudo fpm --force --chdir /tmp/dist/xmlrpc-c -p "${build_dir}/xmlrpc-c_${VERSION}.deb" --input-type dir --output-type deb --name xmlrpc-c --version "${VERSION}" --description "xmlrpc-c v${VERSION} compiled by MediaEase" || {
            echo "Error packaging xmlrpc-c"
            exit 1
        }
        sudo dpkg -i "${build_dir}/xmlrpc-c_${VERSION}.deb" >/dev/null
        cd /tmp || exit
        echo "Finished building xmlrpc-c"
    else
        echo "Using cached xmlrpc-c"
    fi
    new_file="${build_dir}/xmlrpc-c_${VERSION}.deb"
    old_file="${output_dir}/xmlrpc-c_${VERSION}.deb"
    archive_if_changed "$new_file" "$old_file" "xmlrpc-c" "$VERSION"
}

# Function to build libtorrent-rakshasa
function build_libtorrent_rakshasa() {
    echo "Building libtorrent-rakshasa"
    cd /tmp || exit
    rm -rf /tmp/libtorrent
    mkdir -p /tmp/libtorrent /tmp/dist/libtorrent-rakshasa
    VERSION=$libtorrentver
    if [[ "${VERSION}" == "0.13.8" ]]; then
        # Use git clone for version 0.13.8
        git clone -b "v${VERSION}" --depth 1 https://github.com/rakshasa/libtorrent.git /tmp/libtorrent >/dev/null 2>&1 || {
            echo "Error cloning libtorrent-rakshasa"
            exit 1
        }
        cd /tmp/libtorrent || exit
        commit_count=$(git rev-list --count HEAD)
        echo "Total commits: ${commit_count}"
        PACKAGE_VERSION="${libtorrentver}-${commit_count}"
        PACKAGE_FILENAME="libtorrent-rakshasa_${libtorrentver}-${commit_count}.deb"
    else
        # Use tarball for other versions
        libtorrentloc="https://github.com/rakshasa/libtorrent/archive/refs/tags/v${libtorrentver}.tar.gz"
        curl -sL "${libtorrentloc}" -o "/tmp/libtorrent-${libtorrentver}.tar.gz"
        tar -xf "/tmp/libtorrent-${libtorrentver}.tar.gz" -C /tmp/libtorrent --strip-components=1
        cd /tmp/libtorrent || exit
        PACKAGE_VERSION="${libtorrentver}"
        PACKAGE_FILENAME="libtorrent-rakshasa_${libtorrentver}.deb"
    fi
    if [[ ${VERSION} =~ ^("0.13.7"|"0.13.8")$ ]]; then
        patch -p1 <"${patches_dir}/libtorrent/throttle-fix-0.13.7-8.patch"
        if [[ ${libtorrentver} == "0.13.8" ]]; then
            patch -p1 <"${patches_dir}/libtorrent/piece-boundary-fix-0.13.8.patch"
        fi
    fi
    if [[ ${VERSION} =~ ^("0.13.6"|"0.13.7")$ ]]; then
        patch -p1 <"${patches_dir}/libtorrent/openssl.patch"
        if pkg-config --atleast-version=1.14 cppunit && [[ ${libtorrentver} == "0.13.6" ]]; then
            patch -p1 <"${patches_dir}/libtorrent/cppunit-libtorrent.patch"
        fi
        if [[ ${VERSION} == "0.13.6" ]]; then
            patch -p1 <"${patches_dir}/libtorrent/bencode-libtorrent.patch"
            patch -p1 <"${patches_dir}/libtorrent/throttle-fix-0.13.6.patch"
        fi
    fi
    if [[ -f "./autogen.sh" ]]; then
        ./autogen.sh >/dev/null || {
            echo "Error running autogen.sh for libtorrent"
            exit 1
        }
    fi
    ./configure --prefix=/usr --enable-aligned >/dev/null || {
        echo "Error configuring libtorrent"
        exit 1
    }
    make -j"$(nproc)" CXXFLAGS="-w ${rtorrentlevel} ${rtorrentflto} ${rtorrentpipe}" >/dev/null || {
        echo "Error building libtorrent"
        exit 1
    }
    make DESTDIR=/tmp/dist/libtorrent-rakshasa install >/dev/null || {
        echo "Error installing libtorrent"
        exit 1
    }
    sudo fpm --force --chdir /tmp/dist/libtorrent-rakshasa --verbose --debug --package "${build_dir}/${PACKAGE_FILENAME}" --input-type dir --output-type deb --name libtorrent --version "${VERSION}" --description "libtorrent-rakshasa v${PACKAGE_VERSION} compiled by MediaEase" || {
        echo "Error packaging libtorrent-rakshasa"
        exit 1
    }
    sudo dpkg -i "${build_dir}/${PACKAGE_FILENAME}" || {
        echo "Error installing libtorrent-rakshasa"
        exit 1
    }
    cd /tmp || exit
    echo "Finished building libtorrent-rakshasa"
    new_file="${build_dir}/${PACKAGE_FILENAME}"
    old_file="${output_dir}/${PACKAGE_FILENAME}"
    archive_if_changed "$new_file" "$old_file" "libtorrent-rakshasa" "$PACKAGE_VERSION"
}

# Function to build rtorrent
function build_rtorrent() {
    echo "Building ${app_name}"
    cd /tmp || exit
    rm -rf /tmp/${app_name} /tmp/dist/${app_name}
    mkdir -p /tmp/${app_name} /tmp/dist/${app_name}
    VERSION=$rtorrentver
    if [[ "${VERSION}" == "0.9.8" ]]; then
        git clone -b "v${rtorrentver}" --depth 1 https://github.com/rakshasa/${app_name}.git /tmp/${app_name} >/dev/null 2>&1 || {
            echo "Error cloning ${app_name}"
            exit 1
        }
        cd /tmp/${app_name} || exit
        commit_count=$(git rev-list --count HEAD)
        echo "Total commits: ${commit_count}"
        PACKAGE_VERSION="${rtorrentver}-${commit_count}"
        PACKAGE_FILENAME="${app_name}_${rtorrentver}-${commit_count}.deb"
    else
        # Use tarball for other versions
        rtorrentloc="https://github.com/rakshasa/${app_name}/archive/refs/tags/v${rtorrentver}.tar.gz"
        curl -sL "${rtorrentloc}" -o "/tmp/${app_name}-${rtorrentver}.tar.gz"
        tar -xzf "/tmp/${app_name}-${rtorrentver}.tar.gz" -C /tmp/${app_name} --strip-components=1
        cd /tmp/${app_name} || exit
        PACKAGE_VERSION="${rtorrentver}"
        PACKAGE_FILENAME="${app_name}_${rtorrentver}.deb"
    fi
    if [[ ${VERSION} == "0.9.8"* ]]; then
        patch -p1 <"${patches_dir}/${app_name}/${app_name}-ml-fixes-0.9.8.patch"
        patch -p1 <"${patches_dir}/${app_name}/${app_name}-scrape-0.9.8.patch"
        patch -p1 <"${patches_dir}/${app_name}/fast-session-loading-0.9.8.patch"
    fi
    patch -p1 <"${patches_dir}/${app_name}/lockfile-fix.patch"
    patch -p1 <"${patches_dir}/xmlrpc/xmlrpc-fix.patch"
    patch -p1 <"${patches_dir}/xmlrpc/xmlrpc-logic-fix.patch"
    patch -p1 <"${patches_dir}/${app_name}/scgi-fix.patch"
    patch -p1 <"${patches_dir}/${app_name}/session-file-fix.patch"
    if [[ ${VERSION} == "0.9.6" ]]; then
        patch -p1 <"${patches_dir}/${app_name}/rtorrent-0.9.6.patch"
        stdc="-std=c++11"
    fi
    if [[ -f "./autogen.sh" ]]; then
        ./autogen.sh >/dev/null || {
            echo "Error running autogen.sh for ${app_name}"
            exit 1
        }
    fi
    ./configure --prefix=/usr --with-xmlrpc-c >/dev/null || {
        echo "Error configuring ${app_name}"
        exit 1
    }
    make -j"$(nproc)" CXXFLAGS="-w ${rtorrentlevel} ${rtorrentflto} ${rtorrentpipe} ${stdc} -g" >/dev/null || {
        echo "Error building ${app_name}"
        exit 1
    }
    make DESTDIR=/tmp/dist/${app_name} install >/dev/null || {
        echo "Error installing ${app_name}"
        exit 1
    }
    echo "build_dir/package_filename: ${build_dir}/${PACKAGE_FILENAME}"
    echo "package_version: ${PACKAGE_VERSION}"
    sudo fpm --force --chdir "/tmp/dist/${app_name}" --verbose --debug --package "${build_dir}/${PACKAGE_FILENAME}" --input-type dir --output-type deb --name rtorrent --version "${rtorrentver}" --description "${app_name} v${PACKAGE_VERSION} compiled by MediaEase" || {
        echo "Error packaging ${app_name}"
        exit 1
    }
    sudo dpkg -i "${build_dir}/${PACKAGE_FILENAME}" || {
        echo "Error installing ${app_name}"
        exit 1
    }
    echo "Finished building ${app_name}"
    new_file="${build_dir}/${PACKAGE_FILENAME}"
    old_file="${output_dir}/${PACKAGE_FILENAME}"
    archive_if_changed "$new_file" "$old_file" "${app_name}" "$PACKAGE_VERSION"
    sudo dpkg -r ${app_name} || {
        echo "Error removing ${app_name}"
        exit 1
    }
    sudo dpkg -r libtorrent || {
        echo "Error removing libtorrent-rakshasa"
        exit 1
    }
}

# Install dependencies
install_depends_rtorrent

# Compile each rtorrent version
for version in "${rt_versions[@]}"; do
    set_rtorrent_version "$version"
    configure_rtorrent
    build_xmlrpc_c
    build_libtorrent_rakshasa
    build_rtorrent
done
