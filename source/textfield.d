/*
 * textfield.d
 * 
 * Copyright (c) 2021 David P Skluzacek
 */

module textfield;
@safe:

import std.conv : to;
import std.range.primitives : front, popFront, empty;
import std.range : chain, take;
import std.algorithm : min, filter, map;
import std.array : array;
import std.string : fromStringz;
import std.utf : toUTFz, codeLength;
import std.typecons : Tuple, tuple;
import std.math : abs;
import std.exception : enforce;

import sdl2.sdl,
       sdl2.renderer,
       sdl2.texture,
       sdl2.ttf;
import util;
import card : highlight_yellow;

enum light_gray = tuple(192, 192, 192);

version (Android) {
    enum y_position_receiving_input = 30;
    enum border_width = 4;
    enum caret_width = 6;
}
else {
    enum border_width = 2;
    enum caret_width = 3;
}

interface TextComponent
{
    bool acceptingTextInput();
    void inputEvent(SDL_TextInputEvent e, ref Renderer r);
    bool keyboardEvent(SDL_KeyboardEvent e, ref Renderer r);
    void paste(in char[] clipboard, ref Renderer r);
}

final class TextField : TextComponent, Focusable, Clickable
{
    mixin ConfigFocusable;
    
    version (Android) {
        mixin Observable!"textInputStarted";
        mixin Observable!"textInputEnded";
    }

    private
    {
        Rectangle box;
        Font font;
        Texture renderedText;
        Focusable onEnterItem;
        dchar[] text;
        size_t maxLength = -1;
        int padding;
        int fontHeight;
        bool isVisible = true;
        bool isEnabled = true;
        bool hovered;
        bool _receivingInput;
        size_t cursorPosition;

        version (Android) {
            int yPosition;
        }
        else {
            SDL_Cursor* defaultCursor;
            SDL_Cursor* hoverCursor;
        }
    }

    this(Font font, Rectangle box, int padding, SDL_Cursor* defaultCursor, SDL_Cursor* hoverCursor)
    {
        enforce!Error(font !is null);
        
        this.font = font;
        this.box = box;
        this.padding = padding;

        version (Android) {
            yPosition = box.y;
        }
        else {
            this.defaultCursor = defaultCursor;
            this.hoverCursor = hoverCursor;
        }
    }

    void setText(string text, ref Renderer renderer)
    {
        this.text = text.to!(dchar[]);
        renderText(renderer);
    }

    string getText() const pure
    {
        return text.to!string;
    }

    void enabled(bool value) @property @trusted
    {
        isEnabled = value;

        if (value == false)
        {
            receivingInput = false;

            if (hovered) {
                version (Android) {}
                else {
                    SDL_SetCursor(defaultCursor);
                }
                hovered = false;
            }
        }
    }

    bool enabled() @property const pure nothrow @nogc 
    {
        return isEnabled;
    }

    void visible(bool visible) @property
    {
        this.isVisible = visible;

        if (! visible) {
            enabled(false);
        }
    }

    void receivingInput(bool value) @property @trusted
    {
        version (Android)
        {
            if (value) {
                notifyObservers!"textInputStarted"();
                box.y = y_position_receiving_input;
                SDL_StartTextInput();
            }
            else if (_receivingInput) {
                SDL_StopTextInput();
                notifyObservers!"textInputEnded"();
                box.y = yPosition;
            }
        }
        _receivingInput = value;
    }

    void maxTextLength(size_t max) @property pure nothrow @nogc
    {
        this.maxLength = max;
    }

    void onEnter(Focusable f) @property pure nothrow @nogc
    {
        this.onEnterItem = f;
    }

    void draw(ref Renderer renderer) @trusted
    {
        if (! isVisible) {
            return;
        }
        renderer.setDrawColor(255, 255, 255);
        renderer.fillRectangle(box);

        auto borderColor = light_gray;

        if (_receivingInput) {
            borderColor = highlight_yellow;
        }
        renderer.drawBorder(box.w - border_width*2, box.h - border_width*2, border_width,
                            Point(box.x + border_width, box.y + border_width), borderColor);

        auto textPos = Point(box.x + padding, box.y + padding);

        if (! renderedText.isNull) {
            renderer.renderCopy(renderedText, textPos.x, textPos.y);
        }

        if (_receivingInput)
        {
            int width;

            if (cursorPosition > 0 || fontHeight == 0) {
                TTF_SizeUTF8(font, text[0 .. cursorPosition].toUTFz!(char*), &width, &fontHeight);
            }
            renderer.setDrawColor(0, 0, 0);
            renderer.fillRectangle(Rectangle(textPos.x + width - caret_width/3, textPos.y, caret_width, fontHeight));
        }
    }

    override bool acceptingTextInput() pure nothrow
    {
        return _receivingInput;
    }

    override void inputEvent(SDL_TextInputEvent e, ref Renderer r) @trusted
    {
        auto str = fromStringz( &e.text[0] );
        auto inputLength = str.codeLength!dchar;

        if (str == "\t" || str == "\n" || str == "\r\n" || str == "\r") {
            return;
        }
        else if (maxLength >= 0 && inputLength + text.length > maxLength) {
            return;
        }

        if (cursorPosition == text.length) {
            text ~= str.to!(dchar[]);
        }
        else {
            text = text[0 .. cursorPosition].chain(str)
                                            .chain(text[cursorPosition .. $])
                                            .array;
        }
        cursorPosition += inputLength;

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
            else if (cursorPosition == text.length - 1) {  //@suppress(dscanner.suspicious.length_subtraction)
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
        else if (e.keysym.scancode == SDL_SCANCODE_RETURN || e.keysym.scancode == SDL_SCANCODE_KP_ENTER)
        {
            if (onEnterItem) {
                onEnterItem.activate();
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

    override void paste(in char[] clipboard, ref Renderer r)
    {
        static assert( is(typeof(clipboard.front) == dchar) );
        assert(clipboard.length > 0);
        
        auto pasted = clipboard.filter!(c => c != '\r' && c != '\t')
                               .map!(ch => ch == '\n' ? ' ' : ch);

        text = text[0 .. cursorPosition].chain(pasted)
                                        .chain(text[cursorPosition .. $])
                                        .take(maxLength)
                                        .array;

        cursorPosition = min(cursorPosition + pasted.codeLength!dchar, maxLength);
        renderText(r);
    }

    override void mouseButtonDown(Point p)
    {
        bool fieldContainsPoint = box.containsPoint(p);
        
        if (_receivingInput && fieldContainsPoint)
        {
            placeCursor(p);
        }
        else if (isEnabled && fieldContainsPoint)
        {
            receivingInput = true;
            placeCursor(p);
        }
        else if (_receivingInput)
        {
            receivingInput = false;
        }
    }

    override void mouseMoved(Point p) @trusted
    {
        version (Android) {
            if ( _receivingInput && box.containsPoint(p) )
            {
                placeCursor(p);
            }
        }
        else {    
            if ( isEnabled && box.containsPoint( p) )
            {
                if (! hovered)
                {
                    SDL_SetCursor(hoverCursor);
                }
                hovered = true;
            }
            else if (hovered)
            {
                SDL_SetCursor(defaultCursor);
                hovered = false;
            }
        }
    }

    override bool focusEnabled() const
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

    override void loseFocus()
    {
        receivingInput = false;
    }

    override void windowFocusNotify(FocusType ft)
    {
    }

    override void mouseButtonUp(Point p)
    {
    }

    override void cursorMoved() pure nothrow @nogc
    {
    }

    override void activate() pure nothrow @nogc
    {
    }

    private void placeCursor(Point p) @trusted
    {
        if (text.length == 0) {
            cursorPosition = 0;
            return;
        }
        int x = p.x - (box.x + padding);
        int width;
        TTF_SizeUTF8(font, text.toUTFz!(char*), &width, null);

        if (x >= width) {
            cursorPosition = text.length;
            return;
        }
        int distance = abs(x);

        foreach (i; 1 .. text.length)
        {
            TTF_SizeUTF8(font, text[0 .. i].toUTFz!(char*), &width, null);
            int measured = abs(x - width);

            if (measured > distance) {
                cursorPosition = i - 1;
                return;
            }
            distance = measured;
        }

        cursorPosition = text.length - 1;  //@suppress(dscanner.suspicious.length_subtraction)
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
            Surface surface;
            scope(exit) SDL_FreeSurface(surface);
            
            surface = TTF_RenderUTF8_Shaded(font,
                text.toUTFz!(char*), SDL_Color(0, 0, 0, 255), SDL_Color(255, 255, 255, 255));  
            renderedText = createTextureFromSurface(rndr, surface);
        }
    }
}