#!/bin/sh

CURRENT_DIR=$(basename "$PWD")

# Initial setup
echo "Setting up..."
DPATH="device/xiaomi/gale"
KPATH="kernel/xiaomi/gale"
VPATH="vendor/xiaomi/gale"
HPATH="hardware/xiaomi"
BOT_TOKEN=""
CONFIG_CHATID=""
CONFIG_ERROR_CHATID=""

# Setup color
YELLOW=$(tput setaf 3)
BOLD=$(tput bold)
RESET=$(tput sgr0)
BOLD_GREEN=${BOLD}$(tput setaf 2)
ROOT_DIRECTORY="$(pwd)"

# Setup URL
export BOT_MESSAGE_URL="https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
export BOT_EDIT_MESSAGE_URL="https://api.telegram.org/bot$BOT_TOKEN/editMessageText"
export BOT_FILE_URL="https://api.telegram.org/bot$BOT_TOKEN/sendDocument"
export BOT_PIN_URL="https://api.telegram.org/bot$BOT_TOKEN/pinChatMessage"

# Color Setup
cyan="\033[96m"
green="\033[92m"
red="\033[91m"
orange="\e[1;35m"
blue="\033[94m"
yellow="\033[93m"
def="\033[0m"

# SF
SF_USERNAME="SOURCEFORGE_USERNAME"
SF_PROJECT="SOURCEFORGE_PROJECT"

if ! [ -d $DPATH ]; then
    read -p "Enter your dt branch: " DTB
fi
if ! [ -d $VPATH ]; then
    read -p "Enter your vt branch: " VTB
fi

if ! [ -d $DPATH ]; then
    echo -e "- ${blue}$DPATH not found, Cloning...${def}"
    git clone -q -b $DTB your_link $DPATH
    if [ -d $DPATH ]; then
        echo -e "[S] ${green}Cloning $DPATH Success${def}"
    else
        echo -e "[E] ${red}Cloning $DPATH Failed!${def}"
    fi
fi

if ! [ -d $VPATH ]; then
    echo -e "- ${blue}$VPATH not found, Cloning...${def}"
    git clone -q -b $VTB your_link $VPATH
    if [ -d $VPATH ]; then
        echo -e "[S] ${green}Cloning $VPATH Success${def}"
    else
        echo -e "[E] ${red}Cloning $VPATH Failed!${def}"
    fi
fi

if ! [ -d $KPATH ]; then
    echo -e "- ${blue}$KPATH not found, Cloning...${def}"
    git clone -q your_link $KPATH --depth 1
    if [ -d $KPATH ]; then
        echo -e "[S] ${green}Cloning $KPATH Success${def}"
        echo -e "[i] ${yellow}Checking out KernelSU-Next${def}"
        sleep 1
        cd $KPATH
        git submodule init --quiet; git submodule update --recursive --quiet
        rm -rf KernelSU-Next/userspace
        sleep 2
        if [ -d "drivers/kernelsu" ]; then
            echo -e "[S] ${green}Succesfully checking out KernelSU-Next${def}"
        else
            echo -e "[E] ${red}Failed Checking out KernelSU-Next${def}"
        fi
        cd -
    else
        echo -e "[E] ${red}Cloning $KPATH Failed!${def}"
    fi
fi

if ! [ -d $HPATH ]; then
    echo -e "- ${blue}$HPATH not found, Cloning...${def}"
    git clone -q your_link $HPATH
    if [ -d $HPATH ]; then
        echo -e "[S] ${green}Cloning $HPATH Success${def}"
    else
        echo -e "[E] ${red}Cloning $HPATH Failed!${def}"
    fi
fi

function sfup() {
    local filepath="$1"
    local remotepath="$2"

    if [ "$#" -ne 2 ]; then
        echo "Usage: $0 <FILE_PATH> <REMOTE_PATH>"
        exit 1
    fi

    if [[ ! -f "$filepath" ]]; then
        echo "File '$filepath' tidak ditemukan."
        return 1
    fi

    echo "Mengunggah '$filepath' ke SourceForge project '$SF_PROJECT' path '$remotepath'..."

    rsync -av --progress "$filepath" "$SF_USERNAME@frs.sourceforge.net:/home/frs/project/$SF_PROJECT/$remotepath/"

    if [[ $? -eq 0 ]]; then
        echo "Upload selesai."
    else
        echo "Upload gagal."
    fi
}

# Fungsi kirim pesan
function send_message() {
    local RESPONSE=$(curl -s "$BOT_MESSAGE_URL" -d chat_id="$2" \
        -d "parse_mode=html" \
        -d "disable_web_page_preview=true" \
        -d text="$1")
    local MESSAGE_ID=$(echo "$RESPONSE" | grep -o '"message_id":[0-9]*' | cut -d':' -f2)
    echo "$MESSAGE_ID"
}

function edit_message() {
    curl -s "$BOT_EDIT_MESSAGE_URL" -d chat_id="$2" \
        -d "parse_mode=html" \
        -d "message_id=$3" \
        -d text="$1"
}

function send_file() {
    curl -s --progress-bar -F document=@"$1" "$BOT_FILE_URL" \
        -F chat_id="$2" \
        -F "disable_web_page_preview=true" \
        -F "parse_mode=html"
}

function upload_file() {
    SERVER=$(curl -s -X GET 'https://api.gofile.io/servers' | grep -Po '(store*)[^"]*' | tail -n 1)
    RESPONSE=$(curl -s -X POST https://${SERVER}.gofile.io/contents/uploadfile -F "file=@$1")
    HASH=$(echo "$RESPONSE" | grep -Po '(https://gofile.io/d/)[^"]*')
    echo "$HASH"
}

function send_message_to_error_chat() {
    local response=$(curl -s -X POST "$BOT_MESSAGE_URL" -d chat_id="$CONFIG_ERROR_CHATID" \
        -d "parse_mode=html" \
        -d "disable_web_page_preview=true" \
        -d text="$1")
    local message_id=$(echo "$response" | grep -o '"message_id":[0-9]*' | cut -d':' -f2)                 
    echo "$message_id"
}

function edit_message_to_error_chat() {
    curl "$BOT_EDIT_MESSAGE_URL" -d chat_id="$2" \
        -d "parse_mode=html" \
        -d "message_id=$3" \
        -d text="$1"
}

function send_file_to_error_chat() {
    curl -s --progress-bar -F document=@"$1" "$BOT_FILE_URL" \
        -F chat_id="$CONFIG_ERROR_CHATID" \
        -F "disable_web_page_preview=true" \
        -F "parse_mode=html"
}

function fetch_progress() {
    local PROGRESS=$(
        sed -n '/ ninja/,$p' "$ROOT_DIRECTORY/build.log" |
            grep -Po '\d+% \d+/\d+' |
            tail -n1 |
            sed -e 's/ / (/; s/$/)/'
    )

    if [ -z "$PROGRESS" ]; then
        echo "Initializing the build system..."
    else
        echo "$PROGRESS"
    fi
}

function setup_env() {
    source build/envsetup.sh
    ccache -M 120G
}

function prepbuild() {
    local roms="$1"
    local productcode="$2"
    local vartype="$3"
    local reltype="$4"

    if [[ -n "$reltype" ]]; then
        lunch ${roms}_${productcode}-${reltype}-${vartype}
        export CONFIG_LUNCH="${roms}_${productcode}-${reltype}-${vartype}"
    else
        lunch ${roms}_${productcode}-${vartype}
        export CONFIG_LUNCH="${roms}_${productcode}-${vartype}"
    fi
}

function start_build() {
    local typerom="$1"
    CORE_COUNT=$(nproc --all)
    CONFIG_COMPILE_JOBS="$CORE_COUNT"
    DEVICE="$(sed -e "s/^.*_//" -e "s/-.*//" <<<"$CONFIG_LUNCH")"
    ROM_NAME="$(sed "s#.*/##" <<<"$(pwd)")"
    OUT="$(pwd)/out/target/product/$DEVICE"
    DUMMY=$(ls "$OUT"/*.zip)
    CONFIG_TARGET="$typerom"
    build_start_message="🟡 | <i>Compiling ROM...</i>

<b>• ROM:</b> <code>$ROM_NAME</code>
<b>• DEVICE:</b> <code>$DEVICE</code>
<b>• JOBS:</b> <code>$CONFIG_COMPILE_JOBS Cores</code>
<b>• PROGRESS</b>: <code>Starting Build...</code>"

    # Cleanup
    if [ -f "out/error.log" ]; then
        rm -f "out/error.log"
    fi

    if [ -f "out/.lock" ]; then
        rm -f "out/.lock"
    fi

    for f in $DUMMY; do
        if [ -f "$f" ]; then
            rm -f "$f"
        fi
    done

    if [ -f "$ROOT_DIRECTORY/build.log" ]; then
        rm -f "$ROOT_DIRECTORY/build.log"
    fi

    build_message_id=$(send_message "$build_start_message" "$CONFIG_CHATID")
    BUILD_START=$(TZ=Asia/Jakarta date +"%s")
    echo -e "$BOLD_GREEN\nStarting to build now...$RESET"
    mka "$CONFIG_TARGET" -j$CONFIG_COMPILE_JOBS 2>&1 | tee -a "$ROOT_DIRECTORY/build.log" &

    until [ -z "$(jobs -r)" ]; do
        if [ "$(fetch_progress)" = "$previous_progress" ]; then
            continue
        fi

        build_progress_message="🟡 | <i>Compiling ROM...</i>

<b>• ROM:</b> <code>$ROM_NAME</code>
<b>• DEVICE:</b> <code>$DEVICE</code>
<b>• JOBS:</b> <code>$CONFIG_COMPILE_JOBS Cores</code>
<b>• PROGRESS:</b> <code>$(fetch_progress)</code>"

        edit_message "$build_progress_message" "$CONFIG_CHATID" "$build_message_id"

        previous_progress=$(fetch_progress)

        sleep 5
    done

    build_progress_message="🟡 | <i>Compiling ROM...</i>

<b>• ROM:</b> <code>$ROM_NAME</code>
<b>• DEVICE:</b> <code>$DEVICE</code>
<b>• JOBS:</b> <code>$CONFIG_COMPILE_JOBS Cores</code>
<b>• PROGRESS:</b> <code>$(fetch_progress)</code>"

    edit_message "$build_progress_message" "$CONFIG_CHATID" "$build_message_id"

    # Upload Build. Upload the output ROM ZIP file to the index.
    BUILD_END=$(TZ=Asia/Jakarta date +"%s")
    DIFFERENCE=$((BUILD_END - BUILD_START))
    HOURS=$(($DIFFERENCE / 3600))
    MINUTES=$((($DIFFERENCE % 3600) / 60))

    if [ -s "out/error.log" ]; then
        # Send a notification that the build has failed.
        build_failed_message="🔴 | <i>ROM compilation failed...</i>

<i>Check out the log below!</i>"

        edit_message_to_error_chat "$build_failed_message" "$CONFIG_ERROR_CHATID" "$build_message_id"
        send_file_to_error_chat "out/error.log" "$CONFIG_ERROR_CHATID"
    else
        ota_file=$(ls "$OUT"/*ota*.zip | tail -n -1)
        [ -n "$ota_file" ] && rm -f "$ota_file"

        boot_file=$(ls "$OUT"/*$DEVICE/boot.img | tail -n -1)
        zip_file=$(ls "$OUT"/*$DEVICE*.zip | tail -n -1)

        echo -e "$BOLD_GREEN\nStarting to upload the ZIP file now...$RESET\n"

        boot_file_url=$(upload_file "$boot_file")
        zip_file_url=$(upload_file "$zip_file")
        zip_file_md5sum=$(md5sum $zip_file | awk '{print $1}')
        zip_file_size=$(ls -sh $zip_file | awk '{print $1}')

        build_finished_message="🟢 | <i>ROM compiled!!</i>

<b>• ROM:</b> <code>$ROM_NAME</code>
<b>• DEVICE:</b> <code>$DEVICE</code>
<b>• SIZE:</b> <code>$zip_file_size</code>
<b>• MD5SUM:</b> <code>$zip_file_md5sum</code>
<b>• BOOT:</b> $boot_file_url
<b>• ROM:</b> $zip_file_url

<i>Compilation took $HOURS hours(s) and $MINUTES minutes(s)</i>

<b>Script by</b> <a href='https://t.me/panzzxz</a>"

        edit_message "$build_finished_message" "$CONFIG_CHATID" "$build_message_id"
    fi
