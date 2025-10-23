#!/bin/bash
set -e

TARGET="$1"
ARCH="$2"
OS_TYPE="$3"
API_LEVEL="$4"
OS_TYPE_LOWER=$(echo "$OS_TYPE" | tr '[:upper:]' '[:lower:]')
FFMPEG_VERSION="8.0"
INSTALL_DIR="$GITHUB_WORKSPACE/ffmpeg_install_${ARCH}" # Use Arch in install dir to avoid conflicts
PACKAGE_NAME="ffmpeg-${FFMPEG_VERSION}-${OS_TYPE_LOWER}-${ARCH}.tar.gz"
SOURCE_DIR="$GITHUB_WORKSPACE/ffmpeg_source_${ARCH}" # Use Arch in source dir

echo "--- Starting FFmpeg build for $OS_TYPE-$ARCH ---"
echo "Target triple: $TARGET"
echo "FFmpeg version: $FFMPEG_VERSION"
echo "Installation directory: $INSTALL_DIR"
echo "Output package: $PACKAGE_NAME"
[[ -n "$API_LEVEL" ]] && echo "Android API Level: $API_LEVEL"

# --- 1. Download and Extract FFmpeg Source ---
echo "Downloading FFmpeg source..."
mkdir -p "$SOURCE_DIR"
cd "$SOURCE_DIR"
# Avoid re-downloading if source already exists (useful for local testing)
if [ ! -f "ffmpeg-${FFMPEG_VERSION}/configure" ]; then
    curl -sL "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz" -o ffmpeg.tar.gz
    echo "Extracting FFmpeg source..."
    tar -xf ffmpeg.tar.gz --strip-components=1
    rm ffmpeg.tar.gz
else
    echo "Source directory already exists, skipping download/extract."
fi
cd "$SOURCE_DIR" # Ensure we are in the source directory

# --- 2. Configure FFmpeg ---
echo "Configuring FFmpeg..."
# Common flags for a minimal static audio build
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
if [[ "$OS_TYPE_LOWER" == "linux" ]]; then
    if [[ "$TARGET" == *"-android"* ]]; then
        echo "Configuring for Android $ARCH (API $API_LEVEL)..."
        # NDK toolchain should be in PATH thanks to setup-ndk action
        TOOLCHAIN_PREFIX=""
        CONFIGURE_ARCH=""
        case "$ARCH" in
            "arm64-v8a")
                TOOLCHAIN_PREFIX="aarch64-linux-android"
                CONFIGURE_ARCH="aarch64"
                ;;
            "armeabi-v7a")
                TOOLCHAIN_PREFIX="armv7a-linux-androideabi"
                CONFIGURE_ARCH="arm"
                ;;
            "x86_64")
                TOOLCHAIN_PREFIX="x86_64-linux-android"
                CONFIGURE_ARCH="x86_64"
                ;;
            "x86")
                TOOLCHAIN_PREFIX="i686-linux-android"
                CONFIGURE_ARCH="x86"
                ;;
            *)
                echo "Unsupported Android architecture: $ARCH"
                exit 1
                ;;
        esac

        # Construct tool paths using the prefix and API level
        CC="${TOOLCHAIN_PREFIX}${API_LEVEL}-clang"
        CXX="${TOOLCHAIN_PREFIX}${API_LEVEL}-clang++"
        AR="llvm-ar"
        RANLIB="llvm-ranlib"
        STRIP="llvm-strip"

        # Check if compiler exists
        if ! command -v $CC &> /dev/null; then
            echo "Error: Android clang compiler not found in PATH: $CC"
            echo "PATH is: $PATH"
            exit 1
        fi

        CONFIG_FLAGS+=(
            "--target-os=android"
            "--arch=$CONFIGURE_ARCH"
            "--cc=$CC"
            "--cxx=$CXX"
            "--ar=$AR"
            "--ranlib=$RANLIB"
            "--strip=$STRIP"
            # Sysroot is usually handled by the NDK clang wrapper, but specify if needed
            # "--sysroot=$ANDROID_NDK_LATEST_HOME/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
            "--cross-prefix=${TOOLCHAIN_PREFIX}-"
            "--enable-jni"      # Required for Android integration
            # Disable features not available/needed on Android
            "--disable-iconv"
            "--disable-xlib"
            # Explicitly disable assembly for problematic archs if needed
            # if [[ "$CONFIGURE_ARCH" == "x86" || "$CONFIGURE_ARCH" == "x86_64" ]]; then
            #   CONFIG_FLAGS+=("--disable-asm")
            # fi
        )
    else
        echo "Configuring for Linux $ARCH..."
        # Standard Linux build, no special flags needed usually
    fi
elif [[ "$OS_TYPE_LOWER" == "macos" ]]; then
    echo "Configuring for macOS $ARCH..."
    # Add macOS specific flags if needed, e.g., SDK path for cross-compilation
    # if [[ "$TARGET" == "x86_64-apple-darwin" ]]; then
    #    CONFIG_FLAGS+=("--arch=x86_64" "--extra-cflags=-mmacosx-version-min=10.11")
    # elif [[ "$TARGET" == "aarch64-apple-darwin" ]]; then
    #    CONFIG_FLAGS+=("--arch=arm64" "--extra-cflags=-mmacosx-version-min=11.0")
    # fi
fi

# Print configure command for debugging
echo "Running ./configure with flags:"
printf '%q ' "${CONFIG_FLAGS[@]}"
echo

# Run configure
./configure "${CONFIG_FLAGS[@]}"

# --- 3. Compile and Install ---
echo "Compiling FFmpeg..."
make -j$(nproc)
echo "Installing FFmpeg..."
make install

# --- 4. Package Artifact ---
echo "Packaging artifact..."
cd "$INSTALL_DIR"
tar -czf "$GITHUB_WORKSPACE/$PACKAGE_NAME" include lib
cd "$GITHUB_WORKSPACE"

echo "--- Successfully built and packaged $PACKAGE_NAME ---"
