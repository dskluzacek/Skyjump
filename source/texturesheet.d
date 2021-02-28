module texturesheet;
@safe:

import std.stdio : File, readln;
import std.typecons;
import std.ascii : isWhite;
import std.conv : parse;
import std.string : strip;
import std.algorithm : findSplit, find;

import sdl2.sdl,
       sdl2.texture,
	   sdl2.renderer;

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

void renderCopyTR()(ref Renderer rndr,
                    TextureRegion source,
                    auto ref const Rectangle destination) @nogc nothrow
{
	rndr.renderCopy(source.texture, source.rectangle, destination);
}

void renderCopyTR()(ref Renderer rndr,
                    TextureRegion source,
                    int x, int y, int w, int h) @nogc nothrow 
{
	rndr.renderCopy(source.texture, source.rectangle, Rectangle(x, y, w, h));
}

void renderCopyExTR()(ref Renderer rndr,
                      TextureRegion source,
	                  auto ref const Rectangle destination,
                      double angleInDegrees,
                      FlipType flipType = FlipType.NONE) @nogc nothrow
{
	rndr.renderCopyEx(source.texture, source.rectangle, destination, angleInDegrees, flipType);
}

TextureSheet loadTextureSheet(string path, Texture texture) @trusted
{
	auto fileIn = File(path, "r");
	Rectangle[string] regions;
	
	while ( ! fileIn.eof() )
	{
		auto line = fileIn.readln();
		
		if ( line.strip() == "" )
			continue;
		
		auto split = findSplit(line, " ");
		auto coords = parseLine!(int, int, int, int)(split[2]);
		regions[ split[0] ] = Rectangle(coords[0], coords[1], coords[2], coords[3]);
	}
	
	return new TextureSheet(texture, regions);
}

template parseLine(TList...)
{
	auto parseLine(const(char)[] line) @safe
	{
		Tuple!TList result;
		
		foreach ( i, type; TList )
		{
			result[i] = line.parse!(type);
			line = line.find!(a => !isWhite(a));
			//munch(line, " \t");
		}
		
		return result;
	}
}

@safe unittest  // parseLine
{
	string line = "1.66 45 \t 67\t33 -2.1";
	auto tup = parseLine!(double, double, int, int, float)(line);
	
	assert(tup[0] == 1.66);
	assert(tup[1] == 45.0);
	assert(tup[2] == 67);
	assert(tup[3] == 33);
	assert(tup[4] == -2.1f);
}