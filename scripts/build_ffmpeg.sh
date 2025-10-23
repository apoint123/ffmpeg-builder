#!/bin/bash
set -e

TARGET="$1"
ARTIFACT_SUFFIX="$2"
RUNNER_OS="$3"
API_LEVEL="$4"

FFMPEG_VERSION="7.1"
INSTALL_DIR="$GITHUB_WORKSPACE/ffmpeg_install_${ARTIFACT_SUFFIX}"
SOURCE_DIR="$GITHUB_WORKSPACE/ffmpeg_source_${ARTIFACT_SUFFIX}"
PACKAGE_NAME="ffmpeg-${FFMPEG_VERSION}-${ARTIFACT_SUFFIX}.tar.gz"

echo "--- Starting FFmpeg build for $ARTIFACT_SUFFIX ---"
echo "Target triple: $TARGET"
echo "FFmpeg version: $FFMPEG_VERSION"
echo "Installation directory: $INSTALL_DIR"
echo "Output package: $PACKAGE_NAME"
[[ -n "$API_LEVEL" ]] && echo "Android API Level: $API_LEVEL"

mkdir -p "$SOURCE_DIR"
cd "$SOURCE_DIR"
if [ ! -f "ffmpeg-${FFMPEG_VERSION}/configure" ]; then
    curl -sL "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz" -o ffmpeg.tar.gz
    echo "Extracting FFmpeg source..."
    tar -xf ffmpeg.tar.gz --strip-components=1
    rm ffmpeg.tar.gz
fi
cd "$SOURCE_DIR"

echo "Configuring FFmpeg..."
CONFIG_FLAGS=(
    "--prefix=$INSTALL_DIR"
    "--enable-static"
    "--disable-shared"
    "--disable-everything"      # Start by disabling everything
    "--disable-programs"        # Don't build ffmpeg, ffplay, ffprobe CLI tools
    "--disable-doc"
    "--disable-network"         # Disable networking protocols
    "--disable-autodetect"      # Don't enable dependencies automatically

    # Disable all video components (decoders, encoders, filters, hwaccels)
    "--disable-avdevice"
    "--disable-avfilter"
    "--disable-swscale"
    "--disable-encoders"
    "--disable-decoders"
    "--disable-hwaccels"
    "--disable-muxers"          # We only need demuxers for input formats
    "--disable-demuxers"
    "--disable-parsers"
    "--disable-bsfs"
    "--disable-protocols"
    "--disable-indevs"
    "--disable-outdevs"

    # Selectively enable required components
    "--enable-avcodec"          # Core codec library
    "--enable-avformat"         # Core format (container) library
    "--enable-avutil"           # Core utility library
    "--enable-swresample"       # Audio resampling library

    # Enable specific demuxers (add more as needed based on supported formats)
    "--enable-demuxer=aac"
    "--enable-demuxer=ac3"
    "--enable-demuxer=aiff"
    "--enable-demuxer=ape"
    "--enable-demuxer=asf"      # WMA
    "--enable-demuxer=flac"
    "--enable-demuxer=matroska" # MKV/MKA/WebM
    "--enable-demuxer=mov"      # MP4/M4A/MOV
    "--enable-demuxer=mp3"
    "--enable-demuxer=ogg"
    "--enable-demuxer=wav"
    "--enable-demuxer=wv"       # WavPack

    # Enable specific decoders (add more as needed)
    "--enable-decoder=aac"
    "--enable-decoder=aac_latm"
    "--enable-decoder=ac3"
    "--enable-decoder=alac"
    "--enable-decoder=als"
    "--enable-decoder=ape"
    "--enable-decoder=flac"
    "--enable-decoder=mp3"      # Includes mp1, mp2, mp3
    "--enable-decoder=opus"
    "--enable-decoder=pcm_alaw"
    "--enable-decoder=pcm_f32be"
    "--enable-decoder=pcm_f32le"
    "--enable-decoder=pcm_f64be"
    "--enable-decoder=pcm_f64le"
    "--enable-decoder=pcm_mulaw"
    "--enable-decoder=pcm_s16be"
    "--enable-decoder=pcm_s16le"
    "--enable-decoder=pcm_s24be"
    "--enable-decoder=pcm_s24le"
    "--enable-decoder=pcm_s32be"
    "--enable-decoder=pcm_s32le"
    "--enable-decoder=pcm_s8"
    "--enable-decoder=pcm_u16be"
    "--enable-decoder=pcm_u16le"
    "--enable-decoder=pcm_u24be"
    "--enable-decoder=pcm_u24le"
    "--enable-decoder=pcm_u32be"
    "--enable-decoder=pcm_u32le"
    "--enable-decoder=pcm_u8"
    "--enable-decoder=vorbis"
    "--enable-decoder=wavpack"
    "--enable-decoder=wmalossless"
    "--enable-decoder=wmapro"
    "--enable-decoder=wmav1"
    "--enable-decoder=wmav2"
    "--enable-decoder=wmavoice"

    # Enable necessary protocols (adjust if you need http etc.)
    "--enable-protocol=file"

    # Ensure Position Independent Code is enabled for static linking into shared objects/executables
    "--enable-pic"
    "--extra-cflags=-fPIC"
    "--extra-ldflags=-fPIC"
)

# --- Platform Specific Configuration ---
# Determine the actual OS type from the artifact suffix for configuration flags
OS_TYPE_LOWER=""
if [[ "$ARTIFACT_SUFFIX" == *"linux"* ]]; then
    OS_TYPE_LOWER="linux"
elif [[ "$ARTIFACT_SUFFIX" == *"macos"* ]]; then
    OS_TYPE_LOWER="macos"
elif [[ "$ARTIFACT_SUFFIX" == *"android"* ]]; then
    OS_TYPE_LOWER="android" # Use "android" for target-os flag
fi

if [[ "$OS_TYPE_LOWER" == "linux" ]]; then
    echo "Configuring for Linux ($ARTIFACT_SUFFIX)..."
    # Standard Linux build
elif [[ "$OS_TYPE_LOWER" == "macos" ]]; then
    echo "Configuring for macOS ($ARTIFACT_SUFFIX)..."
    # macOS specific flags (if any)
elif [[ "$OS_TYPE_LOWER" == "android" ]]; then
    echo "Configuring for Android $ARTIFACT_SUFFIX (API $API_LEVEL)..."
    # Ensure ANDROID_NDK_HOME is set
    if [ -z "$ANDROID_NDK_HOME" ]; then
        echo "Error: ANDROID_NDK_HOME environment variable is not set."
        exit 1
    fi
    TOOLCHAIN_BIN_PATH="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin" # Runner is linux

    TOOLCHAIN_PREFIX=""
    CONFIGURE_ARCH=""
    # Determine arch from ARTIFACT_SUFFIX
    case "$ARTIFACT_SUFFIX" in
        *"arm64-v8a")
            TOOLCHAIN_PREFIX="aarch64-linux-android"
            CONFIGURE_ARCH="aarch64"
            ;;
        *"armeabi-v7a")
            TOOLCHAIN_PREFIX="armv7a-linux-androideabi"
            CONFIGURE_ARCH="arm"
            ;;
        *"x86_64")
            TOOLCHAIN_PREFIX="x86_64-linux-android"
            CONFIGURE_ARCH="x86_64"
            ;;
        *"x86")
            TOOLCHAIN_PREFIX="i686-linux-android"
            CONFIGURE_ARCH="x86"
            ;;
        *)
            echo "Unsupported Android artifact suffix: $ARTIFACT_SUFFIX"
            exit 1
            ;;
    esac

    # Construct full paths to tools
    CC="$TOOLCHAIN_BIN_PATH/${TOOLCHAIN_PREFIX}${API_LEVEL}-clang"
    CXX="$TOOLCHAIN_BIN_PATH/${TOOLCHAIN_PREFIX}${API_LEVEL}-clang++"
    AR="$TOOLCHAIN_BIN_PATH/llvm-ar"
    RANLIB="$TOOLCHAIN_BIN_PATH/llvm-ranlib"
    STRIP="$TOOLCHAIN_BIN_PATH/llvm-strip"

    # Check if the full path to the compiler exists
    if [ ! -f "$CC" ]; then
        echo "Error: Android clang compiler not found at expected path: $CC"
        echo "Please check NDK installation and environment variables."
        exit 1
    fi

    CONFIG_FLAGS+=(
        "--target-os=android" # Use "android" here
        "--arch=$CONFIGURE_ARCH"
        "--cc=$CC"
        "--cxx=$CXX"
        "--ar=$AR"
        "--ranlib=$RANLIB"
        "--strip=$STRIP"
        # Sysroot is usually handled automatically when using the full compiler path
        "--cross-prefix=${TOOLCHAIN_PREFIX}-" # Keep this for FFmpeg's internal toolchain detection
        "--enable-jni"      # Required for Android integration
        # Disable features not available/needed on Android
        "--disable-iconv"
        "--disable-xlib"
    )
fi

echo "Running ./configure with flags:"
printf '%q ' "${CONFIG_FLAGS[@]}"
echo

./configure "${CONFIG_FLAGS[@]}"

echo "Compiling FFmpeg..."
make -j$(nproc)
echo "Installing FFmpeg..."
make install

echo "Packaging artifact..."
cd "$INSTALL_DIR"
tar -czf "$GITHUB_WORKSPACE/$PACKAGE_NAME" include lib
cd "$GITHUB_WORKSPACE"

echo "--- Successfully built and packaged $PACKAGE_NAME ($ARTIFACT_SUFFIX) ---"