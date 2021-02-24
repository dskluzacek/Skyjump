module keyboard;

import sdl2.sdl;

version (Android) {
	struct KeyboardController { }
}
else:

struct KeyboardController
{
	private
	{
		SDL_Scancode quitKey = SDL_SCANCODE_F12;
		@nogc nothrow void delegate() quitHandler;
	}

	@disable this(this);

@safe: @nogc: nothrow:

	void handleEvent(SDL_KeyboardEvent ke) const @trusted
	{
		if (ke.type == SDL_KEYDOWN && ! ke.repeat)
		{
			if (ke.keysym.scancode == quitKey && quitHandler !is null)
				quitHandler();
		}
	}
	
	void setQuitHandler(void delegate() @nogc nothrow handler) pure
	{
		quitHandler = handler;
	}
}
