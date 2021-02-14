module sdl2.texture;

import std.conv,
       std.typecons;
import sdl2.sdl,
       sdl2.renderer;

/// Provides convenient D-style usage of the SDL_TextureAccess enum.
enum TextureAccess : SDL_TextureAccess
{
	STATIC = SDL_TEXTUREACCESS_STATIC,
	STREAMING = SDL_TEXTUREACCESS_STREAMING,
	TARGET = SDL_TEXTUREACCESS_TARGET
}

/// Wraps a pointer to an SDL_Texture, providing SDL operations as member functions.
struct Texture
{
	private SDL_Texture* raw_texture;

@trusted:
@nogc:
nothrow:

	this(SDL_Texture* rawTexture) pure @safe
	{
		assert(rawTexture !is null);
		
		this.raw_texture = rawTexture;
	}
	
	void setBlendMode(SDL_BlendMode mode)
	{
		auto result = SDL_SetTextureBlendMode(raw_texture, mode);
		assert(result == 0, getSDL2Error());
	}
	
	void setAlphaMod(ubyte alpha)
	{
		auto result = SDL_SetTextureAlphaMod(raw_texture, alpha);
		assert(result == 0, getSDL2Error());
	}
	
	void setColorMod(ubyte red, ubyte green, ubyte blue)
	{
		auto result = SDL_SetTextureColorMod(raw_texture, red, green, blue);
		assert(result == 0, getSDL2Error());
	}
	
	void[] lockTexture()(auto ref const Rectangle rect)  
	{
		void* pixels;
		int pitch;
		
		int result = SDL_LockTexture(raw_texture, &rect, &pixels, &pitch);
		assert(result == 0, getSDL2Error());
		
		return pixels[0 .. (pitch * rect.w)];
	}
	
	void unlockTexture()
	{
		SDL_UnlockTexture(raw_texture);
	}

	void queryTexture(out uint format,
	                  out TextureAccess access,
	                  out int width,
	                  out int height)
	{
		SDL_QueryTexture(raw_texture, &format, cast(int*) &access, &width, &height);
	}
	
	void queryTexture(out int width, out int height)
	{
		SDL_QueryTexture(raw_texture, null, null, &width, &height);
	}
	
	Tuple!(int, "w", int, "h") dimensions() @property
	{
		Tuple!(int, "w", int, "h") tup;
		queryTexture(tup.w, tup.h);
		return tup;
	}
	
	int width() @property
	{
		int width;
		SDL_QueryTexture(raw_texture, null, null, &width, null);
		return width;
	}
	
	int height() @property
	{
		int height;
		SDL_QueryTexture(raw_texture, null, null, null, &height);
		return height;
	}
	
	Tuple!(uint, "format", TextureAccess, "accessType") getAttributes()
	{
		uint format;
		TextureAccess access;
		
		SDL_QueryTexture(raw_texture, &format, cast(int*) &access, null, null);
		
		return tuple!("format", "accessType")(format, access);
	}
	
	uint pixelFormat() @property
	{
		uint format;
		SDL_QueryTexture(raw_texture, &format, null, null, null);
		return format;
	}
	
	TextureAccess accessType() @property
	{
		TextureAccess access;
		SDL_QueryTexture(raw_texture, null, cast(int*) &access, null, null);
		return access;
	}
	
	bool isNull() @property pure
	{
		return (raw_texture is null);
	}
	
	SDL_Texture* rawPtr() @property pure
	{
		return raw_texture;
	}
	
	void dispose()
	{
        if (raw_texture !is null)
        {
            SDL_DestroyTexture(raw_texture);
        }
	}
}

