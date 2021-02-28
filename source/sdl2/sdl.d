module sdl2.sdl;

public import bindbc.sdl;
import std.conv : to;
import std.string : fromStringz;
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
 * Wrapper struct that frees the string returned by
 * SDL_GetClipboardText() in its destructor.
 */
struct SDLClipboardText
{
@safe:

    private char[] sdlString = null;

    @disable this();
    @disable this(this);

    static SDLClipboardText getClipboardText() nothrow @nogc @trusted
    {
        SDLClipboardText result = SDLClipboardText.init;
        
        if ( SDL_HasClipboardText() ) {
            result.sdlString = SDL_GetClipboardText().fromStringz;
        }

        return result;
    }
    
    ~this() nothrow @nogc @trusted
    {
        if (sdlString.ptr !is null) {
            SDL_free(sdlString.ptr);
        }
    }

    bool hasText() const nothrow @nogc pure
    {
        return sdlString !is null;
    }

    /**
    * Returns the malloc-ed string retured by SDL without copying. $(BR)
    * DO NOT escape a reference to it outside the scope in which this SDLClipboardText
    * was declared, as it will be freed when this struct goes out of scope.
    */
    const(char[]) get() const nothrow @nogc pure
    {
        return sdlString;
    }
}
