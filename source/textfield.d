module textfield;
@safe:

import std.string : toStringz, fromStringz;
import std.typecons : tuple;
import std.math : abs;

import sdl2.sdl,
       sdl2.renderer,
       sdl2.texture,
       sdl2.ttf;
import util;
import card : highlight_yellow;

enum light_gray = tuple(192, 192, 192);

interface TextComponent
{
    bool acceptingTextInput();
    void inputEvent(SDL_TextInputEvent e, ref Renderer r);
    bool keyboardEvent(SDL_KeyboardEvent e, ref Renderer r);
}

final class TextField : TextComponent, Focusable, Clickable
{
    mixin ConfigFocusable;

    private
    {
        Rectangle box;
        Font font;
        Texture renderedText;
        SDL_Cursor* defaultCursor;
        SDL_Cursor* hoverCursor;
        char[] text;
        int maxLength = -1;
        int padding;
        int fontHeight;
        bool isVisible = true;
        bool isEnabled = true;
        bool hovered;
        bool receivingInput;
        size_t cursorPosition;
    }

    this(Font font, Rectangle box, int padding, SDL_Cursor* defaultCursor, SDL_Cursor* hoverCursor)
    {
        this.font = font;
        this.box = box;
        this.padding = padding;
        this.defaultCursor = defaultCursor;
        this.hoverCursor = hoverCursor;
    }

    void setText(string text, ref Renderer renderer)
    {
        this.text = text.dup;
        renderText(renderer);
    }

    string getText() pure nothrow
    {
        return text.idup;
    }

    void enabled(bool value) @property nothrow @nogc @trusted
    {
        isEnabled = value;

        if (value == false)
        {
            receivingInput = false;

            if (hovered) {
                SDL_SetCursor(defaultCursor);
                hovered = false;
            }
        }
    }

    bool enabled() @property pure nothrow @nogc
    {
        return isEnabled;
    }

    void visible(bool visible) @property nothrow @nogc
    {
        this.isVisible = visible;

        if (! visible) {
            enabled(false);
        }
    }

    void maxTextLength(int max) @property pure nothrow @nogc
    {
        this.maxLength = max;
    }

    void draw(ref Renderer renderer) @trusted nothrow
    {
        if (! isVisible) {
            return;
        }

        renderer.setDrawColor(255, 255, 255);
        renderer.fillRectangle(box);

        if (receivingInput) {
            renderer.setDrawColor(highlight_yellow[]);
        }
        else {
            renderer.setDrawColor(light_gray[]);
        }
        auto textPos = Point(box.x + padding, box.y + padding);

        renderer.drawRectangle(box);
        renderer.drawRectangle(Rectangle(box.x + 1, box.y + 1, box.w - 2, box.h - 2));
        renderer.renderCopy(renderedText, textPos.x, textPos.y);

        if (receivingInput)
        {
            int width;

            if (cursorPosition > 0 || fontHeight == 0) {
                TTF_SizeText(font, text[0 .. cursorPosition].toStringz, &width, &fontHeight);
            }
            renderer.setDrawColor(0, 0, 0);
            renderer.fillRectangle(Rectangle(textPos.x + width - 1, textPos.y, 3, fontHeight));
        }
    }

    override bool acceptingTextInput() pure nothrow
    {
        return receivingInput;
    }

    override void inputEvent(SDL_TextInputEvent e, ref Renderer r) @trusted
    {
        auto str = fromStringz( &e.text[0] );

        if (str == "\t" || str == "\n" || str == "\r\n" || str == "\r") {
            return;
        }
        else if (maxLength >= 0 && str.length + text.length > maxLength) {
            return;
        }

        if (cursorPosition == text.length) {
            text ~= str;

        }
        else {
            text = text[0 .. cursorPosition] ~ str ~ text[cursorPosition .. $];
        }
        cursorPosition += str.length;

        renderText(r);
    }

    override bool keyboardEvent(SDL_KeyboardEvent e, ref Renderer r)
    {
        if (e.type != SDL_KEYDOWN) {
            return false;
        }

        if (e.keysym.sym == SDLK_BACKSPACE || e.keysym.sym == SDLK_KP_BACKSPACE)
        {
            if (text.length == 0 || cursorPosition == 0) {
                return true;
            }
            else if (cursorPosition == text.length) {
                text.length -= 1;
            }
            else {
                text = text[0 .. cursorPosition - 1] ~ text[cursorPosition .. $];
            }
            --cursorPosition;

            renderText(r);
            return true;
        }
        else if (e.keysym.sym == SDLK_DELETE)
        {
            if (text.length == 0 || cursorPosition >= text.length) {
                return true;
            }
            else if (cursorPosition == text.length - 1) {
                text.length -= 1;
            }
            else {
                text = text[0 .. cursorPosition] ~ text[cursorPosition + 1 .. $];
            }

            renderText(r);
            return true;
        }
        else if (e.keysym.scancode == SDL_SCANCODE_RIGHT)
        {
            if (cursorPosition < text.length) {
                ++cursorPosition;
            }
            return true;
        }
        else if (e.keysym.scancode == SDL_SCANCODE_LEFT)
        {
            if (cursorPosition > 0) {
                --cursorPosition;
            }
            return true;
        }
        else if (e.keysym.sym == SDLK_HOME)
        {
            cursorPosition = 0;
        }
        else if (e.keysym.sym == SDLK_END)
        {
            cursorPosition = text.length;
        }

        return false;
    }

    override void mouseButtonDown(Point p) nothrow
    {
        if ( isEnabled && box.containsPoint(p) )
        {
            receivingInput = true;
            placeCursor(p);
        }
        else
        {
            receivingInput = false;
        }
    }

    override void mouseMoved(Point p) nothrow @nogc @trusted
    {
        if ( isEnabled && box.containsPoint( p) )
        {
            if (! hovered) {
                SDL_SetCursor( hoverCursor);
            }
            hovered = true;
        }
        else if (hovered)
        {
            SDL_SetCursor( defaultCursor);
            hovered = false;
        }
    }

    override bool focusEnabled()
    {
        return enabled();
    }

    override void receiveFocus()
    {
        receivingInput = true;
        cursorPosition = text.length;
    }

    override void receiveFocusFrom(Focusable f)
    {
        receiveFocus();
    }

    override void loseFocus() pure nothrow @nogc
    {
        receivingInput = false;
    }

    override void windowFocusNotify(FocusType ft)
    {
    }

    override void mouseButtonUp(Point p) pure nothrow @nogc
    {
    }

    override void cursorMoved() pure nothrow @nogc
    {
    }

    override void activate() pure nothrow @nogc
    {
    }

    private void placeCursor(Point p) @trusted nothrow
    {
        if (text.length == 0) {
            cursorPosition = 0;
            return;
        }
        int x = p.x - (box.x + padding);
        int width;
        TTF_SizeText(font, text.toStringz, &width, null);

        if (x >= width) {
            cursorPosition = text.length;
            return;
        }
        int distance = abs(x);

        foreach (i; 1 .. text.length)
        {
            TTF_SizeText(font, text[0 .. i].toStringz, &width, null);
            int measured = abs(x - width);

            if (measured > distance) {
                cursorPosition = i - 1;
                return;
            }
            distance = measured;
        }

        cursorPosition = text.length - 1;
    }

    private void renderText(ref Renderer rndr) @trusted
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
            Surface surface = TTF_RenderUTF8_Shaded(font, text.toStringz, SDL_Color(0, 0, 0, 255), SDL_Color(255, 255, 255, 255));
            renderedText = createTextureFromSurface(rndr, surface);
            SDL_FreeSurface(surface);
        }
    }
}