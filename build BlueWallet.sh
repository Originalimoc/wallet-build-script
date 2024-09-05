#!/bin/bash

# Set environment variables
export ANDROID_HOME="$HOME/Android/Sdk"
NODE_VERSION="20.x"
KEYSTORE="$HOME/selfBuilt_wallet_key.jks"  # Save absolute path of the keystore
ALIAS="self-built-wallet-key"  # Updated key alias
APK_UNSIGNED="app/build/outputs/apk/release/app-release-unsigned.apk"
APK_SIGNED="app/build/outputs/apk/release/app-release.apk"
SDK_VERSION="34.0.0"
VERSION_NAME="6.6.8_1"
VERSION_CODE="1719592618"
APP_ID_SUFFIX=".selfCustomBuild"

# Function to log messages
log() {
    local level="$1"
    shift
    echo "[$level] $(date +'%Y-%m-%d %H:%M:%S') - $*"
}

read -p "Enter your keystore password: " -s keystore_password
echo
read -p "Confirm your keystore password: " -s confirm_keystore_password
echo
if [ "$keystore_password" != "$confirm_keystore_password" ]; then
    log "ERROR" "Keystore passwords do not match!"
    exit 1
fi

read -p "Enter your key alias password: " -s key_password
echo
read -p "Confirm your key alias password: " -s confirm_key_password
echo
if [ "$key_password" != "$confirm_key_password" ]; then
    log "ERROR" "Key alias passwords do not match!"
    exit 1
fi

# Function to check command success
check_command() {
    if [ $? -ne 0 ]; then
        log "ERROR" "$1"
        exit 1
    fi
}

# Function to generate signing key
generate_signing_key() {
    log "INFO" "Generating new signing key..."

    read -p "Enter your name: " name
    read -p "Enter your organization unit: " organization_unit
    read -p "Enter your city or locality: " city
    read -p "Enter your state or province: " state
    read -p "Enter your country code (e.g., US): " country_code

    keytool -genkey -v -keystore "$KEYSTORE" -keyalg RSA -keysize 2048 -validity 10000 -alias "$ALIAS" \
        -dname "CN=$name, OU=$organization_unit, L=$city, S=$state, C=$country_code" \
        -storepass "$keystore_password" -keypass "$key_password"

    check_command "Failed to generate signing key."
    log "INFO" "Signing key generated at $KEYSTORE."
}

# Update and install necessary packages
log "INFO" "Updating package list and installing necessary packages..."
sudo apt update && sudo apt install -y \
  openjdk-21-jdk \
  wget \
  unzip \
  build-essential \
  git \
  curl \
  ca-certificates \
  gnupg
check_command "Failed to install necessary packages. If repo has no Java 21 manually change script to 17."

log "INFO" "Updating package list and installing necessary packages..."
sudo update-alternatives --set java /usr/lib/jvm/java-21-openjdk-amd64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-21-openjdk-amd64/bin/javac
check_command "Failed to select Java 21."

# Install Node.js 20 LTS and npm
log "INFO" "Installing Node.js $NODE_VERSION..."
curl -fsSL https://deb.nodesource.com/setup_$NODE_VERSION | sudo -E bash -
sudo apt install -y nodejs
check_command "Failed to install Node.js."

# Verify installations
log "INFO" "Verifying installations..."
java -version
node -v
npm -v
git --version

# Install React Native CLI globally
log "INFO" "Installing React Native CLI globally..."
sudo npm install -g react-native-cli
check_command "Failed to install React Native CLI."

# Install Android SDK Command-Line Tools
log "INFO" "Installing Android SDK Command-Line Tools..."
# Remove existing cmdline-tools if it exists
if [ -d "$ANDROID_HOME/cmdline-tools" ]; then
    log "INFO" "Removing existing cmdline-tools directory..."
    rm -rf "$ANDROID_HOME/cmdline-tools"
fi

mkdir -p "$ANDROID_HOME/cmdline-tools"
pushd "$ANDROID_HOME/cmdline-tools" > /dev/null
wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O cmdline-tools.zip
unzip cmdline-tools.zip
mv cmdline-tools latest
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
popd > /dev/null

# Accept licenses
log "INFO" "Accepting Android SDK licenses..."
yes | sdkmanager --licenses

# Install essential SDK components
log "INFO" "Installing essential SDK components..."
sdkmanager "platform-tools" "platforms;android-34" "build-tools;$SDK_VERSION"
check_command "Failed to install SDK components."

# Add build-tools to PATH
export PATH="$ANDROID_HOME/build-tools/$SDK_VERSION:$PATH"

# Check if the keystore exists, if not, generate one
if [ ! -f "$KEYSTORE" ]; then
    log "INFO" "Keystore not found at $KEYSTORE. Generating a new one..."
    generate_signing_key
else
    log "INFO" "Keystore found at $KEYSTORE."
fi

# Remove existing BlueWallet directory if it exists
if [ -d "./BlueWallet/" ]; then
    log "INFO" "Removing existing BlueWallet directory..."
    rm -rf "./BlueWallet/"
fi

# Clone the BlueWallet repository into the current directory
log "INFO" "Cloning the BlueWallet repository into the current directory..."
#git config --global http.sslVerify false  # Disable SSL verification if necessary
git clone https://github.com/BlueWallet/BlueWallet.git
check_command "Failed to clone the repository."

# Change to the cloned directory
pushd BlueWallet > /dev/null

# Install project dependencies
log "INFO" "Installing project dependencies..."
npm install
check_command "Failed to install project dependencies."

# Ensure the SDK location is set in local.properties
log "INFO" "Setting up SDK location in local.properties..."
echo "sdk.dir=$ANDROID_HOME" > android/local.properties

# Modify the build.gradle file to update version and packageId
log "INFO" "Updating build.gradle for custom version and packageId..."
BUILD_GRADLE_FILE="android/app/build.gradle"
sed -i 's/versionName "[^"]*"/versionName "'$VERSION_NAME'"/' $BUILD_GRADLE_FILE
sed -i 's/versionCode [0-9]\+/versionCode '$VERSION_CODE'/' $BUILD_GRADLE_FILE
sed -i 's/applicationId "\(.*\)"/applicationId "\1'$APP_ID_SUFFIX'"/' $BUILD_GRADLE_FILE

log "INFO" "Updating new packageId in google-services.json..."
GOOGLE_SERVICE_FILE="android/app/google-services.json"
sed -i 's/\"package_name\": "\(.*\)"/\"package_name\": "\1'$APP_ID_SUFFIX'"/' $GOOGLE_SERVICE_FILE

# Build the APK
cd android
log "INFO" "Building the release APK..."
./gradlew assembleRelease
check_command "Failed to build the APK."
log "INFO" "APK generated at: $(pwd)/$APK_UNSIGNED"

# Sign the APK and rename it
log "INFO" "Signing the APK..."
apksigner sign --ks "$KEYSTORE" --ks-key-alias "$ALIAS" --ks-pass pass:"$keystore_password" --key-pass pass:"$key_password" "$APK_UNSIGNED"
check_command "Failed to sign the APK."
mv "$APK_UNSIGNED" "$APK_SIGNED"
check_command "Failed to rename the APK."

log "INFO" "Successfully signed and renamed to $APK_SIGNED"

# Return to the original directory
popd > /dev/null
