#!/bin/sh

ldc2 -Oz --release --boundscheck=on -I=~/.dub/packages/bindbc-sdl-0.19.1/bindbc-sdl/source \
-I=~/.dub/packages/bindbc-loader-0.3.2/bindbc-loader/source \
-i  -d-version=SDL_Image -d-version=SDL_Mixer -d-version=SDL_TTF -mtriple=armv7a--linux-android \
source/sdl2/image.d source/sdl2/mixer.d source/sdl2/renderer.d source/sdl2/sdl.d \
source/sdl2/texture.d source/sdl2/ttf.d source/sdl2/window.d source/animation.d  \
source/background.d source/button.d source/card.d source/client.d source/draganddrop.d \
source/gamemodel.d source/keyboard.d source/label.d source/net.d source/player.d \
source/playergrid.d source/textfield.d source/texturesheet.d source/theme.d source/util.d \
-shared -of=armv7a/libmain.so -L-soname -Llibmain.so -L-llog -L-landroid -L-lEGL -L-lGLESv1_CM

ldc2 -Oz --release --boundscheck=on -I=~/.dub/packages/bindbc-sdl-0.19.1/bindbc-sdl/source \
-I=~/.dub/packages/bindbc-loader-0.3.2/bindbc-loader/source \
-i  -d-version=SDL_Image -d-version=SDL_Mixer -d-version=SDL_TTF -mtriple=aarch64--linux-android \
source/sdl2/image.d source/sdl2/mixer.d source/sdl2/renderer.d source/sdl2/sdl.d \
source/sdl2/texture.d source/sdl2/ttf.d source/sdl2/window.d source/animation.d  \
source/background.d source/button.d source/card.d source/client.d source/draganddrop.d \
source/gamemodel.d source/keyboard.d source/label.d source/net.d source/player.d \
source/playergrid.d source/textfield.d source/texturesheet.d source/theme.d source/util.d \
-shared -of=aarch64/libmain.so -L-soname -Llibmain.so -L-llog -L-landroid -L-lEGL -L-lGLESv1_CM

cp armv7a/libmain.so skyjump-android/app/libs/armeabi-v7a/
cp aarch64/libmain.so skyjump-android/app/libs/arm64-v8a/
