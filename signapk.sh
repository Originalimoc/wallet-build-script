#!/bin/bash

# Function to find apksigner
find_apksigner() {
    local sdk_path="$HOME/Android/Sdk"
    local apksigner_path="$sdk_path/build-tools/*/apksigner"

    # Use 'find' to locate apksigner in build-tools
    for path in $apksigner_path; do
        if [ -x "$path" ]; then
            echo "$path"
            return
        fi
    done

    echo "apksigner not found in $sdk_path/build-tools" >&2
    exit 1
}

# Check if the correct number of arguments are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <key_path> <key_passphrase> <apk_path>"
    exit 1
fi

# Assign arguments to variables
KEY_PATH="$1"
KEY_PASSPHRASE="$2"
APK_PATH="$3"

# Find the apksigner executable
APKSIGNER=$(find_apksigner)

# Sign the APK
"$APKSIGNER" sign --ks "$KEY_PATH" --ks-pass pass:"$KEY_PASSPHRASE" "$APK_PATH"

# Check if the signing was successful
if [ $? -eq 0 ]; then
    echo "APK signed successfully."
else
    echo "Failed to sign APK." >&2
    exit 1
fi
