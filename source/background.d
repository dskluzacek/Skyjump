module background;
@safe:

import sdl2.sdl;
import sdl2.texture;
import sdl2.window;
import sdl2.renderer;

final class Background
{
    private Texture texture;

    this(Texture t) pure nothrow
    {
        this.texture = t;
    }

    void render(ref Renderer rndr, ref Window window)
    {
        auto windowDim = window.dimensions;
        auto textureDim = texture.dimensions;

        int tilesHorizontal = windowDim.w / textureDim.w;
        int tilesVertical = windowDim.h / textureDim.h;

        for (int j = 0; j <= tilesHorizontal; ++j)
        {
            for (int k = 0; k <= tilesVertical; ++k)
            {
                rndr.renderCopy(texture, j * textureDim.w, k * textureDim.h);
            }
        }
    }
}