module sdl2.window;

import std.string : toStringz;
import std.conv : to;
import std.typecons : Tuple, tuple;
import sdl2.sdl, sdl2.renderer;

/**
 * Wraps a pointer to an SDL_Window, providing SDL operations as member functions. $(BR)
 * Copying is disabled. Destroys the window automatically in its destructor.
 */
struct Window
{
    private
    {
        SDL_Window* raw_window;
        bool isDestroyed = false;
    }

@trusted: //stfu

    this( in char[] title,
          int x, int y,
          int width, int height,
          SDL_WindowFlags flags = cast(SDL_WindowFlags) 0 )
    {
        this.raw_window = SDL_CreateWindow(title.toStringz, x, y, width, height, flags);
        
        sdl2Enforce(raw_window !is null, "SDL_CreateWindow failed");
    }
    
    @disable this(this);
    
    ~this() @nogc nothrow
    {
        dispose();
    }
    
    void dispose() @nogc nothrow
    {
        if (! isDestroyed && raw_window !is null)
        {
            SDL_DestroyWindow(raw_window);
            isDestroyed = true;
        }
    }
    
    Renderer createRenderer(SDL_RendererFlags flags, int index = -1)
    {
        auto raw = SDL_CreateRenderer(raw_window, index, flags);
        
        sdl2Enforce(raw !is null, "SDL_CreateRenderer failed");
        return Renderer(raw);
    }
    
    void setTitle(in char[] title) nothrow
    {
        SDL_SetWindowTitle(raw_window, title.toStringz);
    }
    
@nogc:
nothrow:
    
    bool testFlag(uint flag)
    {
        auto flags = SDL_GetWindowFlags(raw_window);
        return (flag & flags) != 0;
    }
    
    bool isInputGrabbed()
    {
        return cast(bool) SDL_GetWindowGrab(raw_window);
    }
    
    Point position()
    {
        Point result;
        SDL_GetWindowPosition(raw_window, &result.x, &result.y);
        return result;
    }
    
    void position(Point p) @property
    {
        setPosition(p.x, p.y);
    }
    
    Tuple!(int, "w", int, "h") dimensions()
    {
        Tuple!(int, "w", int, "h") dims;
        SDL_GetWindowSize(raw_window, &(dims.w), &(dims.h));
        return dims;
    }
    
    int width()
    {
        int width;
        SDL_GetWindowSize(raw_window, &width, null);
        return width;
    }
    
    int height()
    {
        int height;
        SDL_GetWindowSize(raw_window, null, &height);
        return height;
    }
    
    int id()
    {
        return SDL_GetWindowID(raw_window);
    }
    
    bool visible() @property //stfu
    {
        return testFlag(SDL_WINDOW_SHOWN);
    }
    
    void visible(bool visible) @property
    {
        if (visible)
            SDL_ShowWindow(raw_window);
        else
            SDL_HideWindow(raw_window);
    }
    
    void icon(Surface surface) @property
    {
        SDL_SetWindowIcon(raw_window, surface);
    }
    
    void setBordered(bool bordered)
    {
        SDL_SetWindowBordered(raw_window, bordered ? SDL_TRUE : SDL_FALSE);
    }
    
    void setFullscreen(uint flag)
    {
        SDL_SetWindowFullscreen(raw_window, flag);
    }
    
    void setInputGrabbed(bool grabbed)
    {
        SDL_SetWindowGrab(raw_window, grabbed ? SDL_TRUE : SDL_FALSE);
    }
    
    void setPosition(int x, int y)
    {
        SDL_SetWindowPosition(raw_window, x, y);
    }
    
    void setDimensions(int width, int height)
    {
        SDL_SetWindowSize(raw_window, width, height);
    }
    
    void setMinimumSize(int width, int height)
    {
        SDL_SetWindowMinimumSize(raw_window, width, height);
    }
    
    void setMaximumSize(int width, int height)
    {
        SDL_SetWindowMaximumSize(raw_window, width, height);
    }
    
    void maximize()
    {
        SDL_MaximizeWindow(raw_window);
    }
    
    void minimize()
    {
        SDL_MinimizeWindow(raw_window);
    }
    
    void restore()
    {
        SDL_RestoreWindow(raw_window);
    }
    
    void raise()
    {
        SDL_RaiseWindow(raw_window);
    }
}
