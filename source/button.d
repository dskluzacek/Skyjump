/*
 * button.d
 * 
 * Copyright (c) 2021 David P Skluzacek
 */

module button;
@safe:

import std.typecons : tuple;
import std.math : round;

import sdl2.sdl,
       sdl2.renderer,
       sdl2.texture,
       sdl2.ttf;
import texturesheet,
       label,
       util;
import card : pale_indigo, highlight_yellow;

enum button_blue = tuple(47, 135, 181);
enum hovered_color = tuple(cast(ubyte) round(button_blue[0] * pale_indigo[0] / 255.0f),
                           cast(ubyte) round(button_blue[1] * pale_indigo[1] / 255.0f),
                           cast(ubyte) round(button_blue[2] * pale_indigo[2] / 255.0f));

enum x2_sized_ui_button_ht = 80;
enum label_pixel_adjustment = 1;

final class Button : Clickable, Focusable
{
    version (Android) {
        mixin MouseDownActivation;
    }
    else {
        mixin MouseUpActivation;
    }
    mixin BasicFocusable;
    mixin ConfigFocusable;

    private
    {
        Label label;
        bool isVisible = true;

        static TextureRegion cornerTexture;
    }

    this(int x, int y, int width, int height, string text, Font font, ref Renderer renderer)
    {
        setRectangle(Rectangle(x, y, width, height));

        label = new Label(text, font, SDL_Color(255, 255, 255, 255));
        () @trusted { label.setRenderer(&renderer); } ();
        label.enableAutoPosition(x + width / 2, y + label_pixel_adjustment + height / 2,
                                 HorizontalPositionMode.CENTER, VerticalPositionMode.CENTER);
        label.autoReRender = true;
    }

    this(Rectangle dimensions, string text, Font font, ref Renderer renderer)
    {
        this(dimensions.x, dimensions.y, dimensions.w, dimensions.h, text, font, renderer);
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
            drawBorder(renderer, box.w, box.h, 8, Point(box.x, box.y), highlight_yellow[]);
        }
        else if ( focusType == FocusType.WEAK && ! shouldBeHighlighted() ) {
            drawBorder(renderer, box.w, box.h, 8, Point(box.x, box.y), pale_indigo[]);
        }

        if ((shouldBeHighlighted() && windowFocusType != FocusType.STRONG) || focusType == FocusType.STRONG) {
            renderer.setDrawColor(hovered_color[]);
            cornerTexture.texture.setColorMod(pale_indigo[]);
        }
        else {
            renderer.setDrawColor(button_blue[]);
        }
        auto corner_w = getCornerDimension(cornerTexture.width);
        auto corner_h = getCornerDimension(cornerTexture.height);

        renderer.fillRectangle(Rectangle(box.x + corner_w - 2, box.y, box.w - 2 * corner_w + 4, box.h));
        renderer.fillRectangle(Rectangle(box.x, box.y + corner_h - 2, box.w, box.h - 2 * corner_h + 4));
        
        renderer.renderCopyTR(cornerTexture, box.x, box.y, corner_w, corner_h);
        renderer.renderCopyExTR(cornerTexture,
                                Rectangle(box.x + box.w - corner_w, box.y, corner_w, corner_h),
                                0, FlipType.HORIZONTAL);
        renderer.renderCopyExTR(cornerTexture,
                                Rectangle(box.x, box.y + box.h - corner_h, corner_w, corner_h),
                                0, FlipType.VERTICAL);
        renderer.renderCopyExTR(cornerTexture, Rectangle(box.x + box.w - corner_w,
                                                         box.y + box.h - corner_h,
                                                         corner_w,
                                                         corner_h), 0, FlipType.BOTH);
        cornerTexture.texture.setColorMod(255, 255, 255);

        label.draw(renderer);
    }

    override bool focusEnabled() const
    {
        return this.enabled();
    }

    static setCornerTexture(TextureRegion tr)
    {
        cornerTexture = tr;
    }

    private int getCornerDimension(int nativeSize)
    {
        if (box.h >= x2_sized_ui_button_ht) {
            return nativeSize * 2;
        }
        else {
            return nativeSize;
        }
    }
}

abstract class MouseDownButton : Clickable
{
    mixin MouseDownActivation;
}

final class ContextButton : MouseDownButton
{
    private
    {
        Label label;
        bool isVisible = false;
    }

    this(string text, int height, Font font, ref Renderer renderer)
    {
        label = new Label(text, font, SDL_Color(255, 255, 255, 255));
        label.renderText(renderer);
        
        box.w = label.getWidth() + height;
        box.h = height;
    }

    void show(Point triggerPoint) nothrow 
    {   
        box.x = (triggerPoint.x >= 960 ? triggerPoint.x - box.w - 125 : triggerPoint.x + 125);
        box.y = triggerPoint.y;

        label.setPosition(box.x + box.w / 2, box.y + label_pixel_adjustment + box.h / 2,
                          HorizontalPositionMode.CENTER, VerticalPositionMode.CENTER);

        this.enabled = true;
        this.visible = true;
    }

    bool acceptsClick(Point p)
    {
        return this.enabled && box.containsPoint(p);
    }

    override void mouseButtonDown(Point position)
    {
        super.mouseButtonDown(position);
        
        if (isVisible) {
            this.visible = false;
        }
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
        renderer.setDrawColor(button_blue[]);
        renderer.fillRectangle(box);
        label.draw(renderer);
    }
}
