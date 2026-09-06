#!/bin/bash --login

# Define the directory and download URL
TOOLS_DIR="$HOME/.app-installer"
BUNDLETOOLS_DIR="$TOOLS_DIR/bundletool"
DOWNLOAD_URL="https://github.com/google/bundletool/releases/download/1.18.1/bundletool-all-1.18.1.jar"  # Replace with actual URL
BUNDLETOOLS_EXEC="$BUNDLETOOLS_DIR/bundletool.jar"
_TARGET=""
while [[ $# -gt 0 ]]
do
    key="$1"
    case $key in
        -T|--target)
        if [ $# -lt 2 ] || [ -z "$2" ]; then
            echo "Error: $1 requires a target file." >&2
            exit 1
        fi
        _TARGET="$2"
        shift # past argument
        shift # past value
        ;;
        *)    # unknown option
        POSITIONAL+=("$1") # save it in an array for later
        shift # past argument
        ;;
    esac
done

if [ ! -f "$_TARGET" ]; then
	echo -e "target file not exists !";
	exit 1
fi

if [[ "$_TARGET" =~ \.[iI][pP][aA]$ ]]; then
	if ! command -v ideviceinstaller >/dev/null 2>&1; then
        echo "ideviceinstaller not found. Downloading and installing..."
        if ! command -v brew >/dev/null 2>&1; then
            echo "Error: Homebrew not found. Please install Homebrew first."
            exit 1
        fi

        if ! brew install ideviceinstaller; then
            echo "Error: Failed to install ideviceinstaller."
            exit 1
        fi

        if ! command -v ideviceinstaller >/dev/null 2>&1; then
            echo "Error: ideviceinstaller executable not found after installation."
            exit 1
        fi

        echo "ideviceinstaller successfully installed."
    fi

	ideviceinstaller install "$_TARGET"
	if [ $? -ne 0 ]; then
        echo "Failed in iOS installation!"
        exit 1
    fi

	echo -e "Install Successfully!";
	exit
fi

case "$_TARGET" in
    *.[aA][pP][kK]|*.[aA][pP][kK][sS]|*.[aA][aA][bB]) ;;
    *)
        echo "Error: Unsupported file type. Expected apk, aab, apks or ipa." >&2
        exit 1
        ;;
esac

WORK_DIR=""
cleanup() {
    if [ -n "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    echo "Error: $1" >&2
    exit 1
}

prepare_work_dir() {
    if [ -z "$WORK_DIR" ]; then
        mkdir -p "$TOOLS_DIR" || fail "Failed to create tool directory."
        WORK_DIR=$(mktemp -d "$TOOLS_DIR/.tmp.XXXXXX") || fail "Failed to create temporary directory."
    fi
}

download() {
    echo "Downloading $1"
    curl -fL --retry 2 --connect-timeout 15 --max-time 600 "$1" -o "$2" || fail "Download failed: $1"
}

ensure_adb() {
    for candidate in "$(command -v adb)" "${ANDROID_HOME:+$ANDROID_HOME/platform-tools/adb}" "${ANDROID_SDK_ROOT:+$ANDROID_SDK_ROOT/platform-tools/adb}" "$HOME/Library/Android/sdk/platform-tools/adb" "$HOME/Android/Sdk/platform-tools/adb" "$TOOLS_DIR/platform-tools/adb"; do
        if [ -x "$candidate" ] && "$candidate" version >/dev/null 2>&1; then
            ADB_EXEC="$candidate"
            return
        fi
    done

    case "$(uname -s)" in
        Darwin) platform="darwin" ;;
        Linux)
            [ "$(uname -m)" = "x86_64" ] || fail "Automatic adb download requires Linux x86_64."
            platform="linux"
            ;;
        *) fail "Automatic adb download supports macOS and Linux only." ;;
    esac
    prepare_work_dir
    download "https://dl.google.com/android/repository/platform-tools-latest-$platform.zip" "$WORK_DIR/platform-tools.zip"
    unzip -q "$WORK_DIR/platform-tools.zip" -d "$WORK_DIR/adb" || fail "Failed to extract Platform Tools."
    "$WORK_DIR/adb/platform-tools/adb" version >/dev/null 2>&1 || fail "Downloaded adb is not executable."
    rm -rf "$TOOLS_DIR/platform-tools" || fail "Failed to replace cached Platform Tools."
    mv "$WORK_DIR/adb/platform-tools" "$TOOLS_DIR/platform-tools" || fail "Failed to cache Platform Tools."
    ADB_EXEC="$TOOLS_DIR/platform-tools/adb"
}

java_usable() {
    [ -x "$1" ] || return 1
    local version_output
    version_output=$("$1" -version 2>&1) || return 1
    [[ "$version_output" =~ version[[:space:]]+\"([0-9]+) ]] && [ "${BASH_REMATCH[1]}" -ge 17 ]
}

ensure_java() {
    local mac_java_home=""
    if [ -x /usr/libexec/java_home ]; then
        mac_java_home=$(/usr/libexec/java_home -v 17+ 2>/dev/null)
    fi
    for candidate in "${JAVA_HOME:+$JAVA_HOME/bin/java}" "$(command -v java)" "${mac_java_home:+$mac_java_home/bin/java}" "$TOOLS_DIR/java/Contents/Home/bin/java" "$TOOLS_DIR/java/bin/java"; do
        if java_usable "$candidate"; then
            JAVA_EXEC="$candidate"
            return
        fi
    done

    case "$(uname -s)" in
        Darwin) platform="mac" ;;
        Linux) platform="linux" ;;
        *) fail "Automatic Java download supports macOS and Linux only." ;;
    esac
    case "$(uname -m)" in
        arm64|aarch64) architecture="aarch64" ;;
        x86_64) architecture="x64" ;;
        *) fail "Unsupported Java architecture." ;;
    esac
    prepare_work_dir
    download "https://api.adoptium.net/v3/binary/latest/17/ga/$platform/$architecture/jre/hotspot/normal/eclipse" "$WORK_DIR/java.tar.gz"
    mkdir -p "$WORK_DIR/java" || fail "Failed to create Java directory."
    tar -xzf "$WORK_DIR/java.tar.gz" -C "$WORK_DIR/java" --strip-components=1 || fail "Failed to extract Java."
    local java_relative="bin/java"
    if [ "$platform" = "mac" ]; then
        java_relative="Contents/Home/bin/java"
    fi
    java_usable "$WORK_DIR/java/$java_relative" || fail "Downloaded Java runtime is not usable."
    rm -rf "$TOOLS_DIR/java" || fail "Failed to replace cached Java."
    mv "$WORK_DIR/java" "$TOOLS_DIR/java" || fail "Failed to cache Java."
    JAVA_EXEC="$TOOLS_DIR/java/$java_relative"
}

ensure_bundletool() {
    for candidate in "$BUNDLETOOLS_EXEC" "$HOME/.bundletool/bundletool.jar"; do
        if [ -s "$candidate" ] && "$JAVA_EXEC" -jar "$candidate" version >/dev/null 2>&1; then
            BUNDLETOOLS_EXEC="$candidate"
            return
        fi
    done

    prepare_work_dir
    download "$DOWNLOAD_URL" "$WORK_DIR/bundletool.jar"
    "$JAVA_EXEC" -jar "$WORK_DIR/bundletool.jar" version >/dev/null 2>&1 || fail "Downloaded bundletool is not usable."
    mkdir -p "$BUNDLETOOLS_DIR" || fail "Failed to create bundletool directory."
    mv "$WORK_DIR/bundletool.jar" "$BUNDLETOOLS_EXEC" || fail "Failed to cache bundletool."
}

ensure_adb
echo "Using adb: $ADB_EXEC"

if [[ "$_TARGET" =~ \.[aA][pP][kK]$ ]]; then
	"$ADB_EXEC" install "$_TARGET"
	INSTALL_STATUS=$?
	if [ "$INSTALL_STATUS" -ne 0 ]; then
        echo "Failed in Android installation!"
        exit "$INSTALL_STATUS"
    fi
	echo -e "Install Successfully!";
	exit
fi

ensure_java
ensure_bundletool
echo "Using Java: $JAVA_EXEC"
echo "Using bundletool: $BUNDLETOOLS_EXEC"

if [[ "$_TARGET" =~ \.[aA][pP][kK][sS]$ ]]; then
	"$JAVA_EXEC" -jar "$BUNDLETOOLS_EXEC" install-apks --adb="$ADB_EXEC" --apks="$_TARGET"
	if [ $? -ne 0 ]; then
        echo -e "\033[1;31m[`date "+%Y-%m-%d %H:%M:%S"`]Failed in installation!\033[0m"
        exit 1
    fi
elif [[ "$_TARGET" =~ \.[aA][aA][bB]$ ]]; then
	# 创建临时目录存储下载的文件
	prepare_work_dir
	TEMP_DIR="$WORK_DIR/build"
	mkdir -p "$TEMP_DIR" || fail "Failed to create build directory."
	echo "Temporary directory created: $TEMP_DIR"

	"$JAVA_EXEC" -jar "$BUNDLETOOLS_EXEC" build-apks --bundle="$_TARGET" --output="$TEMP_DIR/temp.apks"
	BUILD_STATUS=$?
	if [ "$BUILD_STATUS" -ne 0 ]; then
        rm -rf "$TEMP_DIR"
        echo "Failed to build APKs!"
        exit "$BUILD_STATUS"
    fi

    # # 抽取aab包名
    # /Users/yuyl_field/Library/Android/sdk/build-tools/34.0.0/aapt dump xmltree $TEMP_DIR/temp.apks AndroidManifest.xml > $TEMP_DIR/AndroidManifest.xml
    # if [ $? -ne 0 ]; then
    #   echo "Error: Failed to dump AndroidManifest.xml"
    #   exit 1
    # fi

    # # Parse package name (look for package="..." attribute)
    # TARGET_PACKAGE_NAME=$(grep -o 'package="[^"]*"' $TEMP_DIR/AndroidManifest.xml | cut -d'"' -f2)
    
    # if adb shell pm list packages | grep ${TARGET_PACKAGE_NAME}; then
    #   echo "Uninstalling existing app: ${TARGET_PACKAGE_NAME}"
    #   adb uninstall -k ${TARGET_PACKAGE_NAME}
    #   if [ $? -ne 0 ]; then
    #     echo "Warning: Failed to uninstall app (continuing anyway)"
    #   fi
    # fi

	"$JAVA_EXEC" -jar "$BUNDLETOOLS_EXEC" install-apks --adb="$ADB_EXEC" --apks="$TEMP_DIR/temp.apks"
	INSTALL_STATUS=$?

	# 清理临时目录
	rm -rf "$TEMP_DIR"

	if [ "$INSTALL_STATUS" -ne 0 ]; then
        echo -e "\033[1;31m[`date "+%Y-%m-%d %H:%M:%S"`]Failed in installation!\033[0m"
        exit "$INSTALL_STATUS"
    fi
fi

echo -e "\033[1;32m[`date "+%Y-%m-%d %H:%M:%S"`]Installed Successfully!\033[0m"


