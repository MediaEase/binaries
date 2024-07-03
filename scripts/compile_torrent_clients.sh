#!/bin/bash

# Declare global variables
declare -g patches_dir
declare -g output_dir
declare -g archive_dir
declare -g rtorrentlevel
declare -g rtorrentpipe
declare -g stdc

# Assign values to global variables
patches_dir="$(pwd)/patches"
output_dir="$(pwd)/dist/current"
archive_dir="$(pwd)/dist/archive"
build_dir="$(pwd)/dist/build"

# Function to calculate hash of a file
calculate_hash() {
    local file_path="$1"
    sha256sum "$file_path" | awk '{print $1}'
}

# Function to compare hashes and return true if they differ
has_changed() {
    local new_file="$1"
    local old_file="$2"
    if [[ ! -f "$old_file" ]]; then
        return 0
    fi
    local new_hash
    new_hash=$(calculate_hash "$new_file")
    local old_hash
    old_hash=$(calculate_hash "$old_file")
    [[ "$new_hash" != "$old_hash" ]]
}

# Function to archive old binaries if the new ones have changed
archive_if_changed() {
    local new_file="$1"
    local old_file="$2"
    local app_name="$3"

    if [[ ! -f "$new_file" ]]; then
        echo "New file $new_file does not exist. Skipping archive process."
        return
    fi

    if [[ -f "$old_file" ]] && has_changed "$new_file" "$old_file"; then
        timestamp=$(date +%Y%m%d)
        archive_subdir="${archive_dir}/${app_name}"
        mkdir -p "$archive_subdir"
        mv "$old_file" "${archive_subdir}/${app_name}_${timestamp}.deb"
        # Retain only the latest 3 versions in the archive
        files=("${archive_subdir}/${app_name}"*)
        if [[ ${#files[@]} -gt 3 ]]; then
            for ((i = 0; i < ${#files[@]} - 3; i++)); do
                rm -f "${files[i]}"
            done
        fi
    fi
    cp "$new_file" "$old_file"
}

# Define the versions to be compiled
versions=("0.9.6" "0.9.7" "0.9.8")

# Function to set rTorrent version parameters
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

# Function to install dependencies
function depends_rtorrent() {
    echo "Installing dependencies"
    cd /tmp || exit
    curl -sL https://github.com/Rudde/mktorrent/archive/v1.1.zip -o mktorrent.zip
    rm -rf /tmp/mktorrent
    unzip -q -d mktorrent -j mktorrent.zip >/dev/null
    cd mktorrent || exit
    make >/dev/null
    make install PREFIX=/usr >/dev/null
    cd /tmp || exit
    rm -rf mktorrent*
    echo "Dependencies installed"
}

# Function to build xmlrpc-c
function build_xmlrpc_c() {
    if [[ ! -d /tmp/xmlrpc-c && ! -f /tmp/xmlrpc-c/config.guess ]]; then
        echo "Building xmlrpc-c"
        rm -rf /tmp/dist/xmlrpc-c
        svn checkout -q http://svn.code.sf.net/p/xmlrpc-c/code/advanced /tmp/xmlrpc-c >/dev/null 2>&1 || {
            echo "Error checking out xmlrpc-c"
            exit 1
        }
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
        make -j"$(nproc)" CFLAGS="-w ${rtorrentflto} ${rtorrentpipe} ${rtorrentlevel}" >/dev/null || {
            echo "Error building xmlrpc-c"
            exit 1
        }
        make DESTDIR=/tmp/dist/xmlrpc-c install >/dev/null || {
            echo "Error installing xmlrpc-c"
            exit 1
        }
        sudo fpm -f -C /tmp/dist/xmlrpc-c -p "${build_dir}/xmlrpc-c_${VERSION}.deb" -s dir -t deb -n xmlrpc-c --version "${VERSION}" --description "xmlrpc-c v${VERSION} compiled by MediaEase" >/dev/null
        dpkg -i "${build_dir}/xmlrpc-c_${VERSION}.deb" >/dev/null
        cd /tmp || exit
    else
        echo "Using cached xmlrpc-c"
    fi
    if [[ ${version} == "0.9.8" ]]; then
        rm -rf /tmp/dist/xmlrpc-c
    fi
    echo "Finished building xmlrpc-c"
    new_file="${build_dir}/xmlrpc-c_${VERSION}.deb"
    old_file="${output_dir}/xmlrpc-c_${VERSION}.deb"
    archive_if_changed "$new_file" "$old_file" "xmlrpc-c"
}

# Function to build libtorrent-rakshasa
function build_libtorrent_rakshasa() {
    echo "Building libtorrent-rakshasa"
    libtorrentloc="https://github.com/rakshasa/libtorrent/archive/refs/tags/v${libtorrentver}.tar.gz"
    cd /tmp || exit
    rm -rf /tmp/libtorrent
    mkdir /tmp/libtorrent
    curl -sL "${libtorrentloc}" -o "/tmp/libtorrent-${libtorrentver}.tar.gz"
    VERSION=$libtorrentver
    tar -xf "/tmp/libtorrent-${libtorrentver}.tar.gz" -C /tmp/libtorrent --strip-components=1
    cd /tmp/libtorrent || exit
    if [[ ${libtorrentver} =~ ^("0.13.7"|"0.13.8")$ ]]; then
        patch -p1 <"${patches_dir}/libtorrent/throttle-fix-0.13.7-8.patch" >/dev/null
        if [[ ${libtorrentver} == "0.13.8" ]]; then
            patch -p1 <"${patches_dir}/libtorrent/piece-boundary-fix-0.13.8.patch" >/dev/null
        fi
    fi
    if [[ ${libtorrentver} =~ ^("0.13.6"|"0.13.7")$ ]]; then
        patch -p1 <"${patches_dir}/libtorrent/openssl.patch" >/dev/null
        if pkg-config --atleast-version=1.14 cppunit && [[ ${libtorrentver} == "0.13.6" ]]; then
            patch -p1 <"${patches_dir}/libtorrent/cppunit-libtorrent.patch" >/dev/null
        fi
        if [[ ${libtorrentver} == "0.13.6" ]]; then
            patch -p1 <"${patches_dir}/libtorrent/bencode-libtorrent.patch" >/dev/null
            patch -p1 <"${patches_dir}/libtorrent/throttle-fix-0.13.6.patch" >/dev/null
        fi
    fi
    ./autogen.sh >/dev/null || {
        echo "Error running autogen.sh for libtorrent"
        exit 1
    }
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
    libtorrent_binary="libtorrent-rakshasa_${rtorrentver}"
    sudo fpm -f -C /tmp/dist/libtorrent-rakshasa -p "${build_dir}/${libtorrent_binary}.deb" -s dir -t deb -n libtorrent-rakshasa --version "${rtorrentver}" --description "libtorrent-rakshasa v${rtorrentver} compiled by MediaEase" >/dev/null
    dpkg -i "${build_dir}/${libtorrent_binary}.deb" >/dev/null
    cd /tmp || exit
    rm -rf /tmp/libtorrent
    echo "Finished building libtorrent-rakshasa"
    new_file="${build_dir}/${libtorrent_binary}.deb"
    old_file="${output_dir}/${libtorrent_binary}.deb"
    archive_if_changed "$new_file" "$old_file" "libtorrent-rakshasa"
}

# Function to build rtorrent
function build_rtorrent() {
    echo "Building rtorrent"
    rtorrentloc="https://github.com/rakshasa/rtorrent/archive/refs/tags/v${rtorrentver}.tar.gz"
    cd /tmp || exit
    rm -rf /tmp/rtorrent*
    mkdir /tmp/rtorrent
    curl -sL "${rtorrentloc}" -o "/tmp/rtorrent-${rtorrentver}.tar.gz"
    tar -xzf "/tmp/rtorrent-${rtorrentver}.tar.gz" -C /tmp/rtorrent --strip-components=1
    VERSION=$rtorrentver
    cd /tmp/rtorrent || exit
    if [[ ${VERSION} == "0.9.8" ]]; then
        patch -p1 <"${patches_dir}/rtorrent/rtorrent-ml-fixes-0.9.8.patch" >/dev/null
        patch -p1 <"${patches_dir}/rtorrent/rtorrent-scrape-0.9.8.patch" >/dev/null
        patch -p1 <"${patches_dir}/rtorrent/fast-session-loading-0.9.8.patch" >/dev/null
    fi
    patch -p1 <"${patches_dir}/rtorrent/lockfile-fix.patch" >/dev/null
    patch -p1 <"${patches_dir}/xmlrpc/xmlrpc-fix.patch" >/dev/null
    patch -p1 <"${patches_dir}/xmlrpc/xmlrpc-logic-fix.patch" >/dev/null
    patch -p1 <"${patches_dir}/rtorrent/scgi-fix.patch" >/dev/null
    patch -p1 <"${patches_dir}/rtorrent/session-file-fix.patch" >/dev/null
    if [[ ${VERSION} == "0.9.6" ]]; then
        patch -p1 <"${patches_dir}/rtorrent/rtorrent-0.9.6.patch" >/dev/null
        stdc="-std=c++11"
    fi
    ./autogen.sh >/dev/null || {
        echo "Error running autogen.sh for rtorrent"
        exit 1
    }
    ./configure --prefix=/usr --with-xmlrpc-c >/dev/null || {
        echo "Error configuring rtorrent"
        exit 1
    }
    make -j"$(nproc)" CXXFLAGS="-w ${rtorrentlevel} ${rtorrentflto} ${rtorrentpipe} ${stdc} -g" >/dev/null || {
        echo "Error building rtorrent"
        exit 1
    }
    make DESTDIR=/tmp/dist/rtorrent install >/dev/null || {
        echo "Error installing rtorrent"
        exit 1
    }
    sudo fpm -f -C "/tmp/dist/rtorrent" -p "${build_dir}/rtorrent_${VERSION}.deb" -s dir -t deb -n rtorrent --version "${VERSION}" --description "rtorrent v${rtorrentver} compiled by MediaEase" >/dev/null
    dpkg -r libtorrent-rakshasa >/dev/null 2>&1
    rm -rf /tmp/rtorrent
    echo "Finished building rtorrent"
    new_file="${build_dir}/rtorrent_${VERSION}.deb"
    old_file="${output_dir}/rtorrent_${VERSION}.deb"
    archive_if_changed "$new_file" "$old_file" "rtorrent"
}

# Install dependencies
depends_rtorrent

# Create directories for hashes, output, and archive if they don't exist
mkdir -p "${output_dir}" "${archive_dir}" "${build_dir}"

# Compile each version
for version in "${versions[@]}"; do
    set_rtorrent_version "$version"
    configure_rtorrent
    build_xmlrpc_c
    build_libtorrent_rakshasa
    build_rtorrent
done
