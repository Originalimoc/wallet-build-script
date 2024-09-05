#!/bin/bash

# Set environment variables
export ANDROID_HOME="$HOME/Android/Sdk"
NODE_VERSION="20.x"
KEYSTORE="$HOME/selfBuilt_wallet_key.jks"  # Save absolute path of the keystore
ALIAS="self-built-wallet-key"  # Updated key alias
APK_UNSIGNED="app/build/outputs/apk/release/app-release-unsigned.apk"
APK_SIGNED="app/build/outputs/apk/release/app-release.apk"
SDK_VERSION="34.0.0"
VERSION_NAME="3.32.2_1"
VERSION_CODE="62534"
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
  openjdk-17-jdk \
  wget \
  unzip \
  build-essential \
  git \
  curl \
  ca-certificates \
  gnupg
check_command "Failed to install necessary packages."

log "INFO" "Updating package list and installing necessary packages..."
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-17-openjdk-amd64/bin/javac
check_command "Failed to select Java 17."

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

# Install Capacitor CLI and Angular CLI globally
log "INFO" "Installing Capacitor CLI and Angular CLI globally..."
sudo npm install -g @capacitor/cli @angular/cli typescript
check_command "Failed to install Capacitor CLI and Angular CLI."

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

# Generate signing key if it doesn't exist
if [ ! -f "$KEYSTORE" ]; then
    log "INFO" "Keystore not found at $KEYSTORE. Generating a new one..."
    generate_signing_key
else
    log "INFO" "Signing key found: $KEYSTORE"
fi

# Remove existing airgap-vault directory if it exists
if [ -d "./airgap-vault/" ]; then
    log "INFO" "Removing existing airgap-vault directory..."
    rm -rf "./airgap-vault/"
fi

# Clone the AirGap Vault repository into the current directory
log "INFO" "Cloning the AirGap Vault repository into the current directory..."
#git config --global http.sslVerify false  # Disable SSL verification if necessary
git clone https://github.com/airgap-it/airgap-vault.git
check_command "Failed to clone the repository."

# Change to the cloned directory
pushd airgap-vault > /dev/null

# Install project dependencies with --legacy-peer-deps to avoid conflicts
log "INFO" "Installing project dependencies..."
npm install --legacy-peer-deps
check_command "Failed to install project dependencies."

# Increase Node.js memory limit and build the project
export NODE_OPTIONS="--max_old_space_size=8192"
log "INFO" "Building the project..."
npm run build
check_command "Failed to build the project."

# Ensure the web assets directory exists
if [ ! -d "www" ]; then
  log "INFO" "Creating placeholder web assets directory..."
  mkdir www
  echo "<html><body><h1>Placeholder</h1></body></html>" > www/index.html
fi

# Sync with Android project
log "INFO" "Syncing with Android project..."
npx cap sync android

# Ensure the missing gradle file is not required or manually create it if needed
CORDOVA_GRADLE_FILE="android/capacitor-cordova-android-plugins/cordova.variables.gradle"
if [ ! -f "$CORDOVA_GRADLE_FILE" ]; then
  log "INFO" "Creating a dummy cordova.variables.gradle file."
  mkdir -p "$(dirname "$CORDOVA_GRADLE_FILE")"
  echo "// Dummy gradle variables" > "$CORDOVA_GRADLE_FILE"
fi

# Ensure the SDK location is set in local.properties
log "INFO" "Setting up SDK location in local.properties..."
echo "sdk.dir=$ANDROID_HOME" > android/local.properties

# Edit the build.gradle file to set the namespace, versioning, and applicationId
log "INFO" "Updating build.gradle with namespace, versioning, and applicationId..."
BUILD_GRADLE_FILE="android/app/build.gradle"
sed -i 's/versionCode [0-9]\+/versionCode '$VERSION_CODE'/' "$BUILD_GRADLE_FILE"
sed -i 's/versionName "[^"]*"/versionName "'$VERSION_NAME'"/' "$BUILD_GRADLE_FILE"
sed -i 's/applicationId "\(.*\)"/applicationId "\1'$APP_ID_SUFFIX'"/' "$BUILD_GRADLE_FILE"
#sed -i 's/namespace "it.airgap.vault"/namespace "it.airgap.vault"/' "$BUILD_GRADLE_FILE"  # don't touch namespace

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
