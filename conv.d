#!/usr/bin/env rdmd

import std.stdio, std.file, std.algorithm, std.string, std.conv, std.typecons,
       std.array;

void main(string[] args)
{
    auto text = readText(args[1]);
    auto lines = text.splitter("\n").array[0 .. $-1];
    
    string name = lines[1].chomp(".png");

    string[] keys;
    Tuple!(ushort, ushort)[] coords;
    Tuple!(ushort, ushort)[] dims;

    for (int i = 6; i < lines.length; i += 7)
    {
        keys ~= lines[i].strip();
    }

    for (int i = 8; i < lines.length; i += 7)
    {
        auto line = lines[i];
        line.findSkip(" xy: ");
        ushort x = line.parse!(ushort);
        line.findSkip(", ");
        ushort y = line.parse!(ushort);
        
        coords ~= tuple(x, y);
    }

    for (int i = 9; i < lines.length; i += 7)
    {
        auto line = lines[i];
        line.findSkip(" size: ");
        ushort w = line.parse!(ushort);
        line.findSkip(", ");
        ushort h = line.parse!(ushort);
        
        dims ~= tuple(w, h);
    }

    char[] output;

    foreach (i, key ; keys)
    {
        auto c = coords[i];
        auto d = dims[i];
        
        stdout.rawWrite!ubyte([key.length.to!ubyte]);
        stdout.rawWrite(key);
        stdout.rawWrite!ushort([c[0], c[1], d[0], d[1]]);
    }
}

