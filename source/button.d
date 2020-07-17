module button;
@safe:

import sdl2.sdl,
       sdl2.renderer,
       sdl2.texture,
       sdl2.ttf;
import label,
       util;
import card : pale_indigo, highlight_yellow;

class Button : Clickable, Focusable
{
    mixin MouseUpActivation;
    mixin BasicFocusable;   

    private
    {
        Label label;
        bool isVisible = true;
        Focusable above;
        Focusable below;
        Focusable left;
        Focusable right;
        Focusable tabNext;
    }

    this(int x, int y, int width, int height, string text, Font font, ref Renderer renderer)
    {
        setRectangle(Rectangle(x, y, width, height));

        label = new Label(text, font);
        () @trusted { label.setRenderer(&renderer); } ();
        label.enableAutoPosition(x + width / 2, y + 2 + height / 2,
                                 HorizontalPositionMode.CENTER, VerticalPositionMode.CENTER);
        label.autoReRender = true;
    }

    void setText(string str)
    {
	    label.setText(str);
    }

    void visible(bool visible) @property pure nothrow @nogc
    {
        this.isVisible = visible;

        if (! visible) {
            this.enabled = false;
        }
    }

    void draw(ref Renderer renderer)
    {
	    if (! isVisible) {
            return;
        }

        if (focusType == FocusType.STRONG) {
            drawBorder(renderer, box.w, box.h, Point(box.x, box.y), highlight_yellow[]);
        }
        else if ( focusType == FocusType.WEAK && ! shouldBeHighlighted() ) {
            drawBorder(renderer, box.w, box.h, Point(box.x, box.y), pale_indigo[]);
        }

        if ((shouldBeHighlighted() && windowFocusType != FocusType.STRONG) || focusType == FocusType.STRONG) {
            renderer.setDrawColor(pale_indigo[]);
	    }
        else {
            renderer.setDrawColor(255, 255, 255);
        }

        renderer.fillRectangle(box);
        label.draw(renderer);
    }

    override Focusable nextUp() @property
    {
        return above !is null ? above : this;
    }

    override Focusable nextDown() @property
    {
        return below !is null ? below : this;
    }

    override Focusable nextLeft() @property
    {
        return left !is null ? left : this;
    }

    override Focusable nextRight() @property
    {
        return right !is null ? right : this;
    }

    override Focusable nextTab() @property
    {
        return tabNext !is null ? tabNext : this;
    }

    override bool focusEnabled()
    {
        return this.enabled();
    }

    void nextUp(Focusable f) @property pure nothrow @nogc
    {
        above = f;
    }

    void nextDown(Focusable f) @property pure nothrow @nogc
    {
        below = f;
    }

    void nextLeft(Focusable f) @property pure nothrow @nogc
    {
        left = f;
    }

    void nextRight(Focusable f) @property pure nothrow @nogc
    {
        right = f;
    }

    void nextTab(Focusable f) @property pure nothrow @nogc
    {
        tabNext = f;
    }
}
