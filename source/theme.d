module theme;
@safe:

import sdl2.sdl;
import sdl2.texture;
import background;
import label;

struct Theme
{
    private
    {
        Texture backgroundTexture;
        SDL_Color primaryColor;
        SDL_Color playerTurnColor;
    }

    this(Texture background, SDL_Color primaryColor, SDL_Color playerTurnColor)
    {
        this.backgroundTexture = background;
        this.primaryColor = primaryColor;
        this.playerTurnColor = playerTurnColor;
    }

    Texture getBackgroundTexture()
    {
        return backgroundTexture;
    }

    SDL_Color getPrimaryTextColor()
    {
        return primaryColor;
    }

    SDL_Color getPlayerTurnTextColor()
    {
        return playerTurnColor;
    }
}

void updateLabelColors(Theme theme, Label[] labels)
{
    foreach (label; labels)
    {
        label.setColor(theme.primaryColor);
    }
}