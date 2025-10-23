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
    tar -xf ffmpeg.tar.gz --strip-components=1
    rm ffmpeg.tar.gz
fi
cd "$SOURCE_DIR"

CONFIG_FLAGS=(
    "--prefix=$INSTALL_DIR"
    "--enable-static"
    "--disable-shared"
    "--disable-everything"
    "--disable-programs"
    "--disable-doc"
    "--disable-network"
    "--disable-autodetect"
    "--disable-avdevice"
    "--disable-avfilter"
    "--disable-swscale"
    "--disable-encoders"
    "--disable-decoders"
    "--disable-hwaccels"
    "--disable-muxers"
    "--disable-demuxers"
    "--disable-parsers"
    "--disable-bsfs"
    "--disable-protocols"
    "--disable-indevs"
    "--disable-outdevs"
    "--enable-avcodec"
    "--enable-avformat"
    "--enable-avutil"
    "--enable-swresample"
    "--enable-protocol=file"
    "--enable-pic"
    "--extra-cflags=-fPIC"
    "--extra-ldflags=-fPIC"
)

DEMUXERS=(
    "aac" "ac3" "aiff" "ape" "asf" "flac" "matroska"
    "mov" "mp3" "ogg" "wav" "wv" "amr" "au" "dts" "dtshd"
    "m4v" "mpc" "mpc8" "rm" "tak" "tta" "truehd"
)

DECODERS=(
    "aac" "aac_latm" "ac3" "alac" "als" "ape" "flac" "mp3" "opus"
    "pcm_alaw" "pcm_f32be" "pcm_f32le" "pcm_f64be" "pcm_f64le"
    "pcm_mulaw" "pcm_s16be" "pcm_s16le" "pcm_s24be" "pcm_s24le"
    "pcm_s32be" "pcm_s32le" "pcm_s8" "pcm_u16be" "pcm_u16le"
    "pcm_u24be" "pcm_u24le" "pcm_u32be" "pcm_u32le" "pcm_u8"
    "vorbis" "wavpack" "wmalossless" "wmapro" "wmav1" "wmav2" "wmavoice"
    "amrnb" "amrwb" "cook" "dca" "eac3" "mlp" "mpc7" "mpc8"
    "ra_144" "ra_288" "shorten" "tak" "tta" "truehd"
)

for demuxer in "${DEMUXERS[@]}"; do
    CONFIG_FLAGS+=("--enable-demuxer=$demuxer")
done
for decoder in "${DECODERS[@]}"; do
    CONFIG_FLAGS+=("--enable-decoder=$decoder")
done

OS_TYPE_LOWER=""
if [[ "$ARTIFACT_SUFFIX" == *"linux"* ]]; then
    OS_TYPE_LOWER="linux"
elif [[ "$ARTIFACT_SUFFIX" == *"macos"* ]]; then
    OS_TYPE_LOWER="macos"
elif [[ "$ARTIFACT_SUFFIX" == *"android"* ]]; then
    OS_TYPE_LOWER="android"
fi

if [[ "$OS_TYPE_LOWER" == "linux" ]]; then
    echo "Configuring for Linux ($ARTIFACT_SUFFIX)..."
elif [[ "$OS_TYPE_LOWER" == "macos" ]]; then
    echo "Configuring for macOS ($ARTIFACT_SUFFIX)..."
elif [[ "$OS_TYPE_LOWER" == "android" ]]; then
    echo "Configuring for Android $ARTIFACT_SUFFIX (API $API_LEVEL)..."
    if [ -z "$ANDROID_NDK_HOME" ]; then
        echo "Error: ANDROID_NDK_HOME environment variable is not set."
        exit 1
    fi
    TOOLCHAIN_BIN_PATH="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"

    TOOLCHAIN_PREFIX=""
    CONFIGURE_ARCH=""
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

    CC="$TOOLCHAIN_BIN_PATH/${TOOLCHAIN_PREFIX}${API_LEVEL}-clang"
    CXX="$TOOLCHAIN_BIN_PATH/${TOOLCHAIN_PREFIX}${API_LEVEL}-clang++"
    AR="$TOOLCHAIN_BIN_PATH/llvm-ar"
    RANLIB="$TOOLCHAIN_BIN_PATH/llvm-ranlib"
    STRIP="$TOOLCHAIN_BIN_PATH/llvm-strip"

    if [ ! -f "$CC" ]; then
        echo "Error: Android clang compiler not found at expected path: $CC"
        echo "Please check NDK installation and environment variables."
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
        "--cross-prefix=${TOOLCHAIN_PREFIX}-"
        "--enable-jni"
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