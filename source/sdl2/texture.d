module sdl2.texture;

import std.conv : to;
import std.typecons;
import std.exception : enforce;
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

@trusted: //stfu

	this(SDL_Texture* rawTexture) pure @safe
	{
		enforce!Error(rawTexture !is null);
		
		this.raw_texture = rawTexture;
	}
	
	void setBlendMode(SDL_BlendMode mode)
	{
		auto result = SDL_SetTextureBlendMode(raw_texture, mode);
		enforce(result == 0, getSDL2Error());
	}
	
	void setAlphaMod(ubyte alpha)
	{
		auto result = SDL_SetTextureAlphaMod(raw_texture, alpha);
		enforce(result == 0, getSDL2Error());
	}
	
	void setColorMod(ubyte red, ubyte green, ubyte blue)
	{
		auto result = SDL_SetTextureColorMod(raw_texture, red, green, blue);
		enforce(result == 0, getSDL2Error());
	}
	
	void[] lockTexture()(auto ref const Rectangle rect)  
	{
		void* pixels;
		int pitch;
		
		int result = SDL_LockTexture(raw_texture, &rect, &pixels, &pitch);
		enforce(result == 0, getSDL2Error());
		
		return pixels[0 .. (pitch * rect.w)];
	}

@nogc:
nothrow:
	
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
	
	Tuple!(int, "w", int, "h") dimensions()
	{
		Tuple!(int, "w", int, "h") tup;
		queryTexture(tup.w, tup.h);
		return tup;
	}
	
	int width()
	{
		int width;
		SDL_QueryTexture(raw_texture, null, null, &width, null);
		return width;
	}
	
	int height()
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
	
	uint pixelFormat()
	{
		uint format;
		SDL_QueryTexture(raw_texture, &format, null, null, null);
		return format;
	}
	
	TextureAccess accessType()
	{
		TextureAccess access;
		SDL_QueryTexture(raw_texture, null, cast(int*) &access, null, null);
		return access;
	}
	
	bool isNull() pure
	{
		return (raw_texture is null);
	}
	
	SDL_Texture* rawPtr() pure
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

