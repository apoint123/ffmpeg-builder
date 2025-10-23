#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
TARGET="$1"      # e.g., x86_64-unknown-linux-gnu (unused in this simple script, but good practice)
ARCH="$2"        # e.g., x64
OS_TYPE="$3"     # e.g., linux
FFMPEG_VERSION="8.0"
INSTALL_DIR="$GITHUB_WORKSPACE/ffmpeg_install"
PACKAGE_NAME="ffmpeg-${FFMPEG_VERSION}-${OS_TYPE}-${ARCH}.tar.gz"
SOURCE_DIR="$GITHUB_WORKSPACE/ffmpeg_source" # Separate directory for source code

echo "--- Starting FFmpeg build for $OS_TYPE-$ARCH ---"
echo "Target triple: $TARGET"
echo "FFmpeg version: $FFMPEG_VERSION"
echo "Installation directory: $INSTALL_DIR"
echo "Output package: $PACKAGE_NAME"

# --- 1. Download and Extract FFmpeg Source ---
echo "Downloading FFmpeg source..."
mkdir -p "$SOURCE_DIR"
cd "$SOURCE_DIR"
curl -sL "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz" -o ffmpeg.tar.gz
echo "Extracting FFmpeg source..."
tar -xf ffmpeg.tar.gz --strip-components=1
rm ffmpeg.tar.gz # Clean up archive

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
    "--disable-postproc"
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
# Only package the include and lib directories
tar -czf "$GITHUB_WORKSPACE/$PACKAGE_NAME" include lib
cd "$GITHUB_WORKSPACE" # Go back to the workspace root

echo "--- Successfully built and packaged $PACKAGE_NAME ---"