/*
 * texturesheet.d
 * 
 * Copyright (c) 2021 David P Skluzacek
 */

module texturesheet;
@safe:

import std.string : toStringz;
import std.exception : enforce;

import sdl2.sdl,
       sdl2.texture,
       sdl2.renderer;

import util : IOException;

final class TextureRegion
{
    private
    {
        Texture _texture;
        Rectangle _rectangle;
    }
    
pure: @nogc: nothrow:
    
    this(Texture texture, Rectangle rect)
    {
        _texture = texture;
        _rectangle = rect;
    }
    
    Texture texture() 
    {
        return _texture;
    }
    
    Rectangle rectangle() 
    {
        return _rectangle;
    }
    
    int width() 
    {
        return _rectangle.w;
    }
    
    int height() 
    {
        return _rectangle.h;
    }
}

final class TextureSheet
{
    private
    {
        Texture _texture;
        TextureRegion[string] _regions;
    }
    
    this(Texture texture, Rectangle[string] rects) pure
    {
        this._texture = texture;
        
        foreach (name, rectangle; rects)
        {
            _regions[name] = new TextureRegion(texture, rectangle);
        }
    }
    
    TextureRegion opIndex(in char[] key) pure nothrow
    {
        return _regions[key];
    }
    
    Texture texture() pure @nogc nothrow
    {
        return _texture;
    }
}

void renderCopyTR(ref Renderer rndr, TextureRegion source, int x, int y) @nogc nothrow
{
    rndr.renderCopy(source.texture, source.rectangle, x, y);
}

void renderCopyTR(ref Renderer rndr,
                  TextureRegion source,
                  in Rectangle destination) @nogc nothrow
{
    rndr.renderCopy(source.texture, source.rectangle, destination);
}

void renderCopyTR(ref Renderer rndr,
                  TextureRegion source,
                  int x, int y, int w, int h) @nogc nothrow 
{
    rndr.renderCopy(source.texture, source.rectangle, Rectangle(x, y, w, h));
}

void renderCopyExTR(ref Renderer rndr,
                    TextureRegion source,
                    in Rectangle destination,
                    double angleInDegrees,
                    FlipType flipType = FlipType.NONE) @nogc nothrow
{
    rndr.renderCopyEx(source.texture, source.rectangle, destination, angleInDegrees, flipType);
}

TextureSheet loadTextureSheet(string path, Texture texture) @trusted
{
    SDL_RWops* file = SDL_RWFromFile(path.toStringz, "rb");
    sdl2Enforce(file !is null, `Failed to read "` ~ path ~ `" using SDL_RWFromFile()`);
	scope (exit) { SDL_RWclose(file); }
	
	Rectangle[string] regions;
	
    ubyte size;
    char[32] buffer;
    size_t result = file.SDL_RWread(&size, 1, 1);

    while (result > 0)
    {
        enforce!IOException(size <= buffer.length);
        file.SDL_RWread(buffer.ptr, 1, size);
        
        ushort x = file.SDL_ReadLE16();
        ushort y = file.SDL_ReadLE16();
        ushort w = file.SDL_ReadLE16();
        ushort h = file.SDL_ReadLE16();

        // SDL_ReadLE16 may return 0 if EOF was reached
        // or if an actual 0 was read
        enforce!IOException(w > 0);
        enforce!IOException(h > 0);

        regions[ buffer[0 .. size].idup ] = Rectangle(x, y, w, h);
        result = file.SDL_RWread(&size, 1, 1);
    }
    
    return new TextureSheet(texture, regions);
}
