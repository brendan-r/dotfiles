
# Install dependencies
sudo apt install -y cmake cmake-data libcairo2-dev libxcb1-dev libxcb-ewmh-dev \
     libxcb-icccm4-dev libxcb-image0-dev libxcb-randr0-dev libxcb-util0-dev    \
     libxcb-xkb-dev pkg-config python-xcbgen xcb-proto libxcb-xrm-dev          \
     libasound2-dev libmpdclient-dev libiw-dev libcurl4-openssl-dev            \
     libxcb-cursor-dev libxcb-composite0-dev


pushd ~/projects/
git clone --recursive https://github.com/jaagr/polybar
mkdir polybar/build
cd polybar/build
cmake ..
sudo make install
popd
