#!/usr/bin/env bash
# @file setup_dev_environment.sh
# @project MediaEase
# @version 1.0.0
# @description This script sets up the development environment for the project on Debian systems.
# @license BSD-3 Clause (Included in LICENSE)
# All rights reserved.

set -euo pipefail
[ "${DEBUG:-false}" == "true" ] && set -x

# Default versions
PHP_VERSION="8.3"
NODE_VERSION="18" # Latest LTS version
USER_NAME=""
BRANCH="main"

# Flags for repositories to clone
INSTALL_HARMONYUI=false
INSTALL_ZEN=false
INSTALL_DOCUMENTATION=false
INSTALL_MEDIAEASE=false
INSTALL_ALL=false

# Function to ensure a package is installed
ensure_installed() {
    local package="$1"
    if ! command -v "$package" &>/dev/null; then
        echo "$package could not be found, installing it..."
        case "$package" in
        better-commit)
            npm install -g better-commit >/dev/null
            ;;
        nodejs)
            curl -sL "https://deb.nodesource.com/setup_$NODE_VERSION.x" | bash - >/dev/null
            apt install -yqq nodejs >/dev/null
            ;;
        php)
            ensure_installed "lsb-release"
            ensure_installed "apt-transport-https"
            ensure_installed "ca-certificates"
            ensure_installed "wget"
            wget -qO - https://packages.sury.org/php/apt.gpg | apt-key add - >/dev/null
            echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list >/dev/null
            apt update -yqq >/dev/null
            apt install -yqq "php$PHP_VERSION-cli" >/dev/null
            ;;
        symfony)
            wget -q https://get.symfony.com/cli/installer -O - | bash >/dev/null
            mv ~/.symfony*/bin/symfony /usr/local/bin/symfony
            ;;
        composer)
            EXPECTED_SIGNATURE="$(wget -q -O - https://composer.github.io/installer.sig)"
            php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
            ACTUAL_SIGNATURE="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"
            if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]; then
                echo 'ERROR: Invalid installer signature' >&2
                rm composer-setup.php
                exit 1
            fi
            php composer-setup.php --install-dir=/usr/local/bin --filename=composer >/dev/null
            rm composer-setup.php
            ;;
        *)
            apt install -yqq "$package" >/dev/null
            ;;
        esac
    fi
}

# Function to clone a repository
clone_repo() {
    local repo_name="$1"
    local repo_url="$2"
    local extra_args="${3:-}"
    if [ ! -d "$repo_name" ]; then
        echo "Cloning ${repo_name}..."
        sudo -u "$USER_NAME" git clone --branch "$BRANCH" "$extra_args" "$repo_url" "$repo_name" >/dev/null
    else
        echo "${repo_name} already exists, skipping clone."
    fi
}

# Function to update submodules
update_submodules() {
    local repo_dir="$1"
    cd "$repo_dir" || exit 1
    for submodule in zen harmonyui; do
        echo "Updating submodule $submodule..."
        git submodule update --init --recursive --remote "$submodule" >/dev/null
        git -C "$submodule/" fetch >/dev/null
        git -C "$submodule/" reset --hard "origin/$BRANCH" >/dev/null
    done
    cd ..
}

# Parse flags
while [[ "$#" -gt 0 ]]; do
    case $1 in
    --user)
        USER_NAME="$2"
        shift
        ;;
    --harmonyui) INSTALL_HARMONYUI=true ;;
    --zen) INSTALL_ZEN=true ;;
    --documentation) INSTALL_DOCUMENTATION=true ;;
    --mediaease) INSTALL_MEDIAEASE=true ;;
    --all) INSTALL_ALL=true ;;
    -b | --branch)
        BRANCH="$2"
        shift
        ;;
    -h | --help)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --user                 Specify user to install dependencies (required if HarmonyUI is installed)"
        echo "  --harmonyui            Include HarmonyUI repository (requires PHP and Node.js)"
        echo "  --zen                  Include Zen repository"
        echo "  --documentation        Include Documentation repository"
        echo "  --mediaease            Include MediaEase repository (includes submodules)"
        echo "  --all                  Include all repositories"
        echo "  -b, --branch           Git branch to clone (default: main)"
        echo "  -h, --help             Show this help message"
        exit 0
        ;;
    *)
        echo "Unknown parameter passed: $1"
        exit 1
        ;;
    esac
    shift
done

# Ensure a user is specified if HarmonyUI is being installed
if $INSTALL_HARMONYUI && [ -z "$USER_NAME" ]; then
    echo "ERROR: --user flag is required when installing HarmonyUI."
    exit 1
fi

# Update system and ensure required packages are installed
apt update -yqq >/dev/null
ensure_installed "git"
ensure_installed "nodejs"
ensure_installed "git-flow"
ensure_installed "better-commit"
$INSTALL_HARMONYUI && ensure_installed "php"

# Set all repositories to be installed if --all flag is provided
if $INSTALL_ALL; then
    INSTALL_HARMONYUI=true
    INSTALL_ZEN=true
    INSTALL_DOCUMENTATION=true
    INSTALL_MEDIAEASE=true
fi

# Repositories to clone
declare -A REPOS=(
    [mflibs]="https://github.com/MediaEase/mflibs.git"
)

$INSTALL_HARMONYUI && REPOS+=([harmonyui]="https://github.com/MediaEase/HarmonyUI.git")
$INSTALL_ZEN && REPOS+=([zen]="https://github.com/MediaEase/zen.git")
$INSTALL_DOCUMENTATION && REPOS+=([documentation]="https://github.com/MediaEase/docs.git")
$INSTALL_MEDIAEASE && REPOS+=([mediaease]="https://github.com/MediaEase/MediaEase.git")

[ -d "/opt/MediaEase" ] && rm -rf /opt/MediaEase/*
# Create directory if it doesn't exist
[ ! -d "/opt/MediaEase" ] && mkdir -p /opt/MediaEase
cd /opt/MediaEase || exit 1

# Clone repositories
for repo in "${!REPOS[@]}"; do
    if [ "$repo" == "mediaease" ]; then
        clone_repo "$repo" "${REPOS[$repo]}" "--recurse-submodules"
        update_submodules "$repo"
    else
        clone_repo "$repo" "${REPOS[$repo]}"
    fi
done

echo "Development environment setup is complete."
