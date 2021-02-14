module sdl2.ttf;

public import bindbc.sdl.ttf;
import std.string : toStringz;
import sdl2.sdl;

/// alias Font = TTF_Font*
alias Font = TTF_Font*;

void initSDL_ttf() @trusted
{
	loadSDLTTF();

	auto result = TTF_Init();
	sdl2Enforce(result == 0, "TTF_Init failed");
}

Font openFont(in char[] file, int size) @trusted
{
    Font font = TTF_OpenFont(file.toStringz, size);

    sdl2Enforce(font !is null, `Error loading font "` ~ file ~ '"');
	return font;
}

