module sdl2.renderer;

import std.traits : Unqual;
import std.typecons : Tuple, tuple;
import std.string : toStringz;
import derelict.sdl2.image;
import sdl2.sdl, sdl2.window, sdl2.texture;

/// Provides convenient D-style usage of the SDL_RendererFlip enum.
enum FlipType
{
	NONE = SDL_FLIP_NONE,
	HORIZONTAL = SDL_FLIP_HORIZONTAL,
	VERTICAL = SDL_FLIP_VERTICAL,
	BOTH = (SDL_FLIP_HORIZONTAL | SDL_FLIP_VERTICAL)
}

/**
 * Wraps a pointer to an SDL_Renderer, providing SDL operations as member functions. $(BR)
 * Copying is disabled. Destroys the renderer automatically in its destructor.
 */
struct Renderer
{
	private
	{
		SDL_Renderer* raw_renderer;
		bool isDestroyed = false;
	}

@trusted:
@nogc:
nothrow:	
	
	this(SDL_Renderer* rawRenderer) pure @safe
	in {
		assert(rawRenderer !is null);
	}
	body
	{
		this.raw_renderer = rawRenderer;
	}
	
	@disable this(this);
	
	~this()
	{
		dispose();
	}
	
	void dispose()
	{
		if (! isDestroyed && raw_renderer !is null)
		{
			SDL_DestroyRenderer(raw_renderer);
			isDestroyed = true;
		}
	}
	
	void present()
	{
		SDL_RenderPresent(raw_renderer);
	}
	
	void clear()
	{
		SDL_RenderClear(raw_renderer);
	}
	
	/**
	 * Copies a portion of the texture to the current rendering target.
	 * 
	 * Params:
	 *        tx   = the texture to copy from
	 *        src  = the source Rectangle, or null for the entire texture
	 *        dest = the destination Rectangle, or null for the entire target
	 */
	void renderCopy(S, T)(Texture tx,
	                      auto ref const S src,
	                      auto ref const T dest) if (isRectOrNull!S && isRectOrNull!T)
	{
		auto s = addressOfOrNull(src);
		auto d = addressOfOrNull(dest);

		SDL_RenderCopy(raw_renderer, tx.rawPtr, s, d);
	}
	
	/**
	 * Copies a portion of the texture to the current rendering target,
	 * with the width and height of the source being kept unchanged.
	 * 
	 * Params:
	 *        tx  = the texture to copy from
	 *        src = the source rectangle
	 *        x   = x coordinate of the destination
	 *        y   = y coordinate of the destination
	 */
	void renderCopy()(Texture tx, auto ref const Rectangle src, int x, int y)
	{
		renderCopy(tx, src, Rectangle(x, y, src.w, src.h));
	}
	
	/**
	 * Copies the entire texture to the current rendering target,
	 * 
	 * Params:
	 *        tx   = the texture to copy from
	 *        x   = x coordinate of the destination
	 *        y   = y coordinate of the destination
	 *        w   = width of the destination rectangle
	 *        h   = height of the destination rectangle
	 */
	void renderCopy(Texture tx, int x, int y, int w, int h)
	{
		renderCopy(tx, null, Rectangle(x, y, w, h));
	}
	
	/**
	 * Copies the entire texture to the current rendering target,
	 * with the width and height of the source being kept unchanged.	 
	 * 
	 * Params:
	 *        tx   = the texture to copy from
	 *        x   = x coordinate of the destination
	 *        y   = y coordinate of the destination
	 */
	void renderCopy(Texture tx, int x, int y)
	{
		renderCopy(tx, null, Rectangle(x, y, tx.dimensions[]));
	}
	
	void renderCopyEx(S, T)(Texture tx,
	                        auto ref const S src,
	                        auto ref const T dest,
	                        double angleInDegrees,
	                        FlipType flipType = FlipType.NONE) if ( isRectOrNull!S
	                        	                                    && isRectOrNull!T )
	{
		auto s = addressOfOrNull(src);
		auto d = addressOfOrNull(dest);
		
		SDL_RenderCopyEx(raw_renderer, tx.rawPtr, s, d, angleInDegrees, null, flipType);
	}
	
	void renderCopyEx(S, T)(Texture tx,
	                        auto ref const S src,
	                        auto ref const T dest,
	                        double angleInDegrees,
	                        auto ref const Point center,
	                        FlipType flipType = FlipType.NONE) if ( isRectOrNull!S
	                        	                                    && isRectOrNull!T )
	{		
		auto s = addressOfOrNull(src);
		auto d = addressOfOrNull(dest);
		
		SDL_RenderCopyEx(raw_renderer, tx.rawPtr, s, d, angleInDegrees, &center, flipType);
	}
	
	void setLogicalSize(int width, int height)
	{
		SDL_RenderSetLogicalSize(raw_renderer, width, height);
	}
	
	void setDrawColor(ubyte r, ubyte g, ubyte b, ubyte a = 255)
	{
		SDL_SetRenderDrawColor(raw_renderer, r, g, b, a);
	}
	
	void setDrawBlendMode(SDL_BlendMode mode)
	{
		SDL_SetRenderDrawBlendMode(raw_renderer, mode);
	}

    Tuple!(float, "x", float, "y") getScale()
    {
        Tuple!(float, "x", float, "y") result;
        SDL_RenderGetScale(raw_renderer, &result.x, &result.y);
        return result;
    }
	
	void setScale(float scaleX, float scaleY)
	{
		SDL_RenderSetScale(raw_renderer, scaleX, scaleY);
	}
	
	void setViewport()(auto ref const Rectangle rect)
	{
		SDL_RenderSetViewport(raw_renderer, &rect);
	}
	
	void setClipRect()(auto ref const Rectangle rect)
	{
		SDL_RenderSetClipRect(raw_renderer, &rect);
	}
	
	bool isRenderTargetSupported()
	{
		return cast(bool) SDL_RenderTargetSupported(raw_renderer);
	}
	
	int setRenderTarget(Texture tx)
	{
		return SDL_SetRenderTarget(raw_renderer, tx.rawPtr);
	}
	
	void drawLine(int x1, int y1, int x2, int y2)
	{
		SDL_RenderDrawLine(raw_renderer, x1, y1, x2, y2);
	}
	
	void drawPoint(int x, int y)
	{
		SDL_RenderDrawPoint(raw_renderer, x, y);
	}
	
	void drawRectangle()(auto ref const Rectangle rect)
	{
		SDL_RenderDrawRect(raw_renderer, &rect);
	}
	
	void fillRectangle()(auto ref const Rectangle rect)
	{
		SDL_RenderFillRect(raw_renderer, &rect);
	}
	
	void drawLines(in Point[] points)
	{
		SDL_RenderDrawLines(raw_renderer, points.ptr, cast(int) points.length);
	}
	
	void drawPoints(in Point[] points)
	{
		SDL_RenderDrawPoints(raw_renderer, points.ptr, cast(int) points.length);
	}
	
	void drawRectangles(in Rectangle[] rectangles)
	{
		SDL_RenderDrawRects(raw_renderer, rectangles.ptr, cast(int) rectangles.length);
	}
	
	void fillRectangles(in Rectangle[] rectangles)
	{
		SDL_RenderFillRects(raw_renderer, rectangles.ptr, cast(int) rectangles.length);
	}
}

Texture loadTexture(ref Renderer renderer, string file) @trusted
{
	auto rawTexture = IMG_LoadTexture(renderer.raw_renderer, file.toStringz);

	sdl2Enforce(rawTexture !is null, `Error loading as texture "` ~ file ~ '"');
	return Texture(rawTexture);
}

Texture createTextureFromSurface(ref Renderer renderer, Surface surface) @trusted
{
	auto rawTexture = SDL_CreateTextureFromSurface(renderer.raw_renderer, surface);
	
	sdl2Enforce(rawTexture !is null, "Error creating texture from surface");
	return Texture(rawTexture);
}

Texture createTexture(ref Renderer renderer,
                      uint pixelFormat,
                      TextureAccess accessType,
                      int w,
                      int h) @trusted
{
	auto rawTexture = SDL_CreateTexture(renderer.raw_renderer, pixelFormat, accessType, w, h);
	
	sdl2Enforce(rawTexture !is null, "Error creating texture (SDL_CreateTexture failed)");
	return Texture(rawTexture);
}

private:

template isRectOrNull(T)
{
	enum isRectOrNull = is(Unqual!T : Rectangle) || is(T == typeof(null));
}

auto addressOfOrNull(T)(ref T value)
{
	static if ( is(Unqual!T == typeof(null)) )
		return null;
	else
		return &value;
}
