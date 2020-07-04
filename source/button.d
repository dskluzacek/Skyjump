module button;
@safe:

import sdl2.sdl,
       sdl2.renderer,
       sdl2.texture,
       sdl2.ttf;
import label,
       util;
import card : pale_indigo;

class Button : Clickable
{
    mixin MouseUpActivation;

    private
    {
        Label label;
        bool isVisible = true;
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

        if ( shouldBeHighlighted() ) {
            renderer.setDrawColor(pale_indigo[]);
	    }
        else {
            renderer.setDrawColor(255, 255, 255);
        }

        renderer.fillRectangle(box);
        label.draw(renderer);
    }
}

