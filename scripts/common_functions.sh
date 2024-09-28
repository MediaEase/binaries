#!/bin/bash

# Shared functions for compilation scripts

# Declare global variables
declare -g output_dir
declare -g archive_dir
declare -g build_dir
declare -g app_name

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
    local version="$4"
    if [[ ! -f "$new_file" ]]; then
        echo "New file $new_file does not exist. Skipping archive process."
        return
    fi

    if [[ -f "$old_file" ]] && has_changed "$new_file" "$old_file"; then
        timestamp=$(date +%Y%m%d)
        archive_subdir="${archive_dir}/${app_name}/${version}"
        mkdir -p "$archive_subdir"
        mv "$old_file" "${archive_subdir}/${app_name}-${version}_${timestamp}.deb"
        # Delete files in the archive that do not contain a version number
        find "$archive_subdir" -type f -name "${app_name}_*.deb" | while read -r archived_file; do
            if [[ ! $(basename "$archived_file") =~ _[0-9]+\.[0-9]+\.[0-9]+([-.][0-9]+)?_[0-9]+\.deb ]]; then
                echo "Deleting file without version number: $archived_file"
                rm -f "$archived_file"
            fi
        done
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

# Function to build archive directories
build_archive_dir() {
    local app_name="$1"
    local version="$2"
    if [ -z "$repo_root" ]; then
        echo "Error: repo_root is not set."
        exit 1
    fi
    output_dir="${repo_root}/dist/current/${app_name}/${version}"
    build_dir="/tmp/dist/build/${app_name}/${version}"
    archive_dir="${repo_root}/dist/archive/${app_name}/${version}"
    mkdir -p "${output_dir}" "${build_dir}" "${archive_dir}"
}
