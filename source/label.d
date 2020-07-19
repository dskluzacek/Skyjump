module label;
@safe:

import std.string : toStringz;
import std.exception : enforce;
import sdl2.sdl,
       sdl2.renderer,
       sdl2.texture,
       sdl2.ttf;

enum BLACK = SDL_Color(0, 0, 0, 255);

enum VerticalPositionMode
{
    TOP,
    CENTER,
    BOTTOM
}

enum HorizontalPositionMode
{
    LEFT,
    CENTER,
    RIGHT
}

final class Label
{
    private
    {
        string text;
        bool visible = true;
        Font font;
        SDL_Color color;
        Point position;
        Texture renderedText;

        bool _autoReRender;
        Renderer* _renderer;

        bool autoPositionEnabled;
        Point autoPosition;
        VerticalPositionMode verticalPositionMode;
        HorizontalPositionMode horizontalPositionMode;
    }

    this(string text, Font font, SDL_Color color = BLACK) pure nothrow
    {
        this.text = text;
        this.font = font;
        this.color = color;
    }

    this(string text, Font font, int x, int y, SDL_Color color = BLACK) pure nothrow
    {
        this(text, font, color);
        setPosition(x, y);
    }

    void setText(string str) @trusted
    {
        if (str == text)
            return;

        text = str;

        if (_autoReRender && _renderer !is null) {
            renderImpl(*_renderer);
        }

        if (autoPositionEnabled) {
            setPosition(autoPosition.x, autoPosition.y, horizontalPositionMode, verticalPositionMode);
        }

    }

    void setColor(SDL_Color color) @trusted
    {
        if (color == this.color)
            return;

	    this.color = color;

        if (_autoReRender && _renderer !is null) {
            renderImpl(*_renderer);
        }
    }

    void setVisible(bool visible) pure @nogc nothrow
    {
        this.visible = visible;
    }

    bool isVisible() pure @nogc nothrow
    {
        return visible;
    }

    void setPosition(int x, int y) pure @nogc nothrow
    {
        position = Point(x, y);
    }

    void setPosition(int x, int y, HorizontalPositionMode hMode, VerticalPositionMode vMode) @trusted nothrow
    {
        int width, height;

        if (vMode != VerticalPositionMode.TOP || hMode != HorizontalPositionMode.LEFT)
        {
            TTF_SizeText(font, text.toStringz, &width, &height);
        }

        final switch (hMode)
        {
        case HorizontalPositionMode.LEFT:
            position.x = x;
            break;
        case HorizontalPositionMode.RIGHT:
            position.x = x - width;
            break;
        case HorizontalPositionMode.CENTER:
            position.x = x - width / 2;
            break;
        }

        final switch (vMode)
        {
        case VerticalPositionMode.TOP:
            position.y = y;
            break;
        case VerticalPositionMode.BOTTOM:
            position.y = y - height;
            break;
        case VerticalPositionMode.CENTER:
            position.y = y - height / 2;
            break;
        }
    }

    void enableAutoPosition(int x, int y, HorizontalPositionMode hMode, VerticalPositionMode vMode)
    {
        autoPositionEnabled = true;
        autoPosition.x = x;
        autoPosition.y = y;
        horizontalPositionMode = hMode;
        verticalPositionMode = vMode;
        setPosition(x, y, hMode, vMode);
    }

    Point getPosition()
    {
        return position;
    }

    void setRenderer(Renderer* renderer) pure
    {
        enforce!Error(renderer !is null, "renderer cannot be null");

        _renderer = renderer;
    }

    void autoReRender(bool value) @property
    {
        _autoReRender = value;

        if (_autoReRender && _renderer !is null)
        {
            renderImpl(*_renderer);
        }
    }

    void renderText(ref Renderer renderer)
    in {
        assert(! _autoReRender);
    }
    body
    {
        renderImpl(renderer);
    }

    void draw(ref Renderer rndr) @nogc nothrow
    {
        if (visible && ! renderedText.isNull)
        {
            rndr.renderCopy(renderedText, position.x, position.y);
        }
    }

    private void renderImpl(ref Renderer rndr) @trusted
    {
        if (! renderedText.isNull)
        {
            renderedText.dispose();
        }

        if (text == "")
        {
            renderedText = Texture.init;
        }
        else
        {
            Surface surface = TTF_RenderUTF8_Blended(font, text.toStringz, color);
            renderedText = createTextureFromSurface(rndr, surface);
            SDL_FreeSurface(surface);
        }
    }
}

