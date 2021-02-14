module sdl2.sdl;

public import bindbc.sdl;
import std.conv,
       std.string,
       std.typecons;
import bindbc.sdl,
       bindbc.sdl.ttf,
       bindbc.sdl.mixer;

/// alias Point = SDL_Point
alias Point = SDL_Point;

/// alias Rectangle = SDL_Rect
alias Rectangle = SDL_Rect;

/// alias Surface = SDL_Surface*
alias Surface = SDL_Surface*;


abstract final class SDL2
{
    /**
     * Loads the SDL2 shared library and does SDL_Init().
     *
     * Params:
     *        flags = the flags to initialize SDL with (passed to SDL_Init)
     * Throws:
     *        SDL2Exception on failure of SDL_Init.
     */
    static void start(uint flags) @trusted
    {
        loadSDL();

        auto result = SDL_Init(flags);
        sdl2Enforce(result == 0, "SDL_Init failed");
    }

    static void quit() @trusted
    {
        SDL_Quit();
    }
}

/**
 * Class for exceptions thrown as a result of SDL2 errors.
 */
final class SDL2Exception : Exception
{
	this(string message, string file = __FILE__, size_t line = __LINE__) pure @safe nothrow
	{
		super(message, file, line);
	}
}

/**
 * Throws an exception (SDL2Exception by default) if the value is false, appending
 * the message from SDL_GetError() to the provided message string
 */
void sdl2Enforce(T = SDL2Exception)(bool value, lazy const(char)[] message) @trusted
{
	if (! value)
	{
		throw new T( message.to!string ~ ": " ~ SDL_GetError().to!string );
	}
}

/**
 * Retrieves the error message from SDL_GetError() and returns it.
 */
const(char)[] getSDL2Error() @trusted @nogc nothrow
{
	return fromStringz( SDL_GetError() );
}

