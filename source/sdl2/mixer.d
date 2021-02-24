module sdl2.mixer;

import std.string : toStringz;
import bindbc.sdl.mixer;
import sdl2.sdl;

/// alias Sound = Mix_Chunk*
alias Sound = Mix_Chunk*;

void initSDL_mixer() @trusted
{
    loadSDLMixer();
}

void openAudio( int frequency = 44_100,
                ushort format = MIX_DEFAULT_FORMAT,
                int channels = 2,
                int chunkSize = 2048 ) @trusted
{
    auto result = Mix_OpenAudio(frequency, format, channels, chunkSize);
    
    sdl2Enforce(result == 0, "Mix_OpenAudio failed");
}

Sound loadWAV(string file) @trusted
{
    auto sound = Mix_LoadWAV(file.toStringz);
    
    sdl2Enforce(sound !is null, `Error loading sound file "` ~ file ~ '"');
    return sound;
}

void play(Sound s, int channel = -1, int loops = 0) @trusted @nogc nothrow
{
    Mix_PlayChannel(channel, s, loops);
}
