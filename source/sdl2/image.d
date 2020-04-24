module sdl2.image;

import std.string : toStringz;
import derelict.sdl2.image;
import sdl2.sdl;

void initSDL_image(int flags = IMG_INIT_PNG) @trusted
{
	DerelictSDL2Image.load();
	
	// returns flags successfully initialized
	auto result = IMG_Init(flags);
	
	sdl2Enforce(result == flags, "IMG_Init failed");
}

Surface loadImage(in char[] file) @trusted
{
	auto surface = IMG_Load(file.toStringz);
	
	sdl2Enforce(surface !is null, `Error loading image "` ~ file ~ '"');
	return surface;
}
