#!/bin/bash

# Declare global variables
declare -g output_dir
declare -g build_dir
declare -g app_name

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(dirname "$script_dir")"
export repo_root
# shellcheck disable=SC1091
source "$(dirname "$0")/common_functions.sh"

libtorrent_path="$1"
boost_path="$2"
qbittorrent_path="$3"
export BOOST_ROOT="$boost_path"

# Define the versions to be compiled
del_versions=("2.1.1")
qbit_versions=("4.6.6" "4.6.7" "5.0.0")

# Function to set Deluge version parameters
function set_deluge_version() {
    case $1 in
    '2.1.1' | 211)
        delugever='2.1.1'
        libtorrentver='2.0.10'
        ;;
    *)
        echo "Error: $1 is not a valid Deluge version"
        exit 1
        ;;
    esac
    app_name="deluge"
    build_archive_dir "${app_name}" "${delugever}"
}

# Function to set qBittorrent version parameters
function set_qbittorrent_version() {
    case $1 in
    '4.6.6' | 466)
        qbitver='4.6.6'
        libtorrentver='2.0.10'
        ;;
    '4.6.7' | 467)
        qbitver='4.6.7'
        libtorrentver='2.0.10'
        ;;
    '5.0.0' | 500)
        qbitver='5.0.0rc1'
        libtorrentver='2.0.10'
        ;;
    *)
        echo "Error: $1 is not a valid qBittorrent version"
        exit 1
        ;;
    esac
    app_name="qbittorrent"
    build_archive_dir "${app_name}" "${qbitver}"
}

# Install dependencies
install_depends_clients

# Function to build libtorrent-rasterbar
function package_libtorrent() {
    local version="$1"
    echo "Packaging libtorrent-rasterbar from ${libtorrent_path}"
    PACKAGE_VERSION="${version}"
    PACKAGE_FILENAME="libtorrent-rasterbar_${PACKAGE_VERSION}.deb"
    DESTDIR="/tmp/dist/libtorrent-rasterbar"
    rm -rf "$DESTDIR"
    mkdir -p "$DESTDIR"
    cp -r "${libtorrent_path}/install_prefix/." "$DESTDIR/" || {
        echo "Error copying libtorrent files"
        exit 1
    }
    cd "$DESTDIR" || exit
    sudo fpm --force --chdir "$DESTDIR" --input-type dir --output-type deb \
        --name libtorrent-rasterbar --version "$PACKAGE_VERSION" \
        --description "libtorrent-rasterbar v${PACKAGE_VERSION} packaged by MediaEase" \
        --package "${build_dir}/${PACKAGE_FILENAME}" || {
        echo "Error packaging libtorrent-rasterbar"
        exit 1
    }
    dpkg -i "${build_dir}/${PACKAGE_FILENAME}" || {
        echo "Error installing libtorrent-rasterbar"
        exit 1
    }
    echo "Finished packaging libtorrent-rasterbar v${version}"
    new_file="${build_dir}/${PACKAGE_FILENAME}"
    old_file="${output_dir}/${PACKAGE_FILENAME}"
    archive_if_changed "$new_file" "$old_file" "libtorrent-rasterbar" "${PACKAGE_VERSION}"
    dpkg -r libtorrent-rasterbar || {
        echo "Error removing libtorrent-rasterbar"
        exit 1
    }
    rm -rf "$DESTDIR"
}

function package_qbittorrent() {
    local version="$1"
    echo "Packaging qBittorrent from ${qbittorrent_path}"
    PACKAGE_VERSION="${version}"
    PACKAGE_FILENAME="qbittorrent_${PACKAGE_VERSION}.deb"
    DESTDIR="/tmp/dist/qbittorrent"
    rm -rf "$DESTDIR"
    mkdir -p "$DESTDIR"
    cp -r "${qbittorrent_path}/install_prefix/." "$DESTDIR/" || {
        echo "Error copying qBittorrent files"
        exit 1
    }
    cd "$DESTDIR" || exit
    sudo fpm --force --chdir "$DESTDIR" --input-type dir --output-type deb \
        --name qbittorrent --version "$PACKAGE_VERSION" \
        --description "qBittorrent v${PACKAGE_VERSION} packaged by MediaEase" \
        --package "${build_dir}/${PACKAGE_FILENAME}" || {
        echo "Error packaging qBittorrent"
        exit 1
    }
    dpkg -i "${build_dir}/${PACKAGE_FILENAME}" || {
        echo "Error installing qBittorrent"
        exit 1
    }
    echo "Finished packaging qBittorrent v${version}"
    new_file="${build_dir}/${PACKAGE_FILENAME}"
    old_file="${output_dir}/${PACKAGE_FILENAME}"
    archive_if_changed "$new_file" "$old_file" "qbittorrent" "${PACKAGE_VERSION}"
    dpkg -r qbittorrent || {
        echo "Error removing qBittorrent"
        exit 1
    }
    rm -rf "$DESTDIR"
}

# Function to build Deluge
function build_deluge() {
    echo "Building Deluge"
    cd /tmp || exit
    rm -rf /tmp/deluge /tmp/dist/deluge
    mkdir -p /tmp/deluge /tmp/dist/deluge
    VERSION=$delugever
    echo "Downloading Deluge ${VERSION}"
    git clone https://github.com/deluge-torrent/deluge.git /tmp/deluge || {
        echo "Error cloning Deluge"
        exit 1
    }
    cd /tmp/deluge || exit
    git checkout "deluge-${VERSION}" || {
        echo "Error checking out Deluge version ${VERSION}"
        exit 1
    }
    python3 -m venv venv
    # shellcheck disable=SC1091
    source venv/bin/activate
    pip install --upgrade pip setuptools
    pip install setuptools_scm six wheel || {
        echo "Error installing required Python packages"
        exit 1
    }
    pip install -r requirements.txt || {
        echo "Error installing Deluge requirements"
        exit 1
    }

    PACKAGE_VERSION="${VERSION}"
    PACKAGE_FILENAME="deluge_${PACKAGE_VERSION}.deb"
    # Build Deluge
    python setup.py build || {
        echo "Error building Deluge"
        exit 1
    }
    # Install into a temporary directory
    DESTDIR="/tmp/dist/deluge"
    python setup.py install --root="$DESTDIR" || {
        echo "Error installing Deluge"
        exit 1
    }
    deactivate
    # Package using fpm
    cd "$DESTDIR" || exit
    sudo fpm --force --chdir "$DESTDIR" --input-type dir --output-type deb \
        --name deluge --version "$PACKAGE_VERSION" \
        --description "Deluge v${PACKAGE_VERSION} compiled by MediaEase" \
        --package "${build_dir}/${PACKAGE_FILENAME}" || {
        echo "Error packaging Deluge"
        exit 1
    }
    dpkg -i "${build_dir}/${PACKAGE_FILENAME}" || {
        echo "Error installing Deluge"
        exit 1
    }
    echo "Finished building Deluge"
    new_file="${build_dir}/${PACKAGE_FILENAME}"
    old_file="${output_dir}/${PACKAGE_FILENAME}"
    archive_if_changed "$new_file" "$old_file" "deluge" "$PACKAGE_VERSION"
    dpkg -r deluge || {
        echo "Error removing Deluge"
        exit 1
    }
    rm -rf /tmp/deluge /tmp/dist/deluge
}

# Compile Deluge
for version in "${del_versions[@]}"; do
    set_deluge_version "$version"
    build_libtorrent_rasterbar "$libtorrentver"
    build_deluge
done

# Compile qBittorrent
for version in "${qbit_versions[@]}"; do
    set_qbittorrent_version "$version"
    package_libtorrent "$libtorrentver"
    package_qbittorrent "$qbitver"
done
