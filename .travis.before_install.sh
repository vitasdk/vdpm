if [ "$TRAVIS_OS_NAME" == "osx" ]; then
    VITASDK_PLATFORM=mac
    mkdir /usr/local/vitasdk
else
    VITASDK_PLATFORM=linux
    sudo apt-get install libc6-i386 lib32stdc++6 lib32gcc1
    sudo mkdir /usr/local/vitasdk
    sudo chown $USER:$USER /usr/local/vitasdk
fi
wget -O "vitasdk-nightly.tar.bz2" "https://bintray.com/vitasdk/vitasdk/download_file?file_path=vitasdk-${VITASDK_PLATFORM}-nightly-${VITASDK_VER}.tar.bz2"
tar xf "vitasdk-nightly.tar.bz2" -C /usr/local/vitasdk --strip-components=1

export VITASDK=/usr/local/vitasdk
export PATH=$VITASDK/bin:$PATH