/*
 * util.d
 * 
 * Copyright (c) 2021 David P Skluzacek
 */

module util;

import std.math : abs, sqrt;
import std.algorithm : remove, min, max;
import std.array : array;
import std.traits;
import std.typecons : Nullable, tuple;
import std.functional : unaryFun, toDelegate;

version (server) {} else {
    import sdl2.sdl : Rectangle, Point;
    import sdl2.renderer;
}

pure float lerp(float value1, float value2, float t) @safe @nogc nothrow
{
    return ((1 - t) * value1) + (t * value2);
}

pure Point lerp()(Point a, Point b, float t) @safe @nogc nothrow
{
    return Point(cast(int) lerp(a.x, b.x, t), cast(int) lerp(a.y, b.y, t));
}

pure bool containsPoint()(Rectangle rect, int x, int y) @safe @nogc nothrow
{
    return ( x >= rect.x && x <= rect.x + rect.w
            && y >= rect.y && y <= rect.y + rect.h );
}

pure bool containsPoint()(Rectangle rect, Point p) @safe @nogc nothrow
{
    return containsPoint(rect, p.x, p.y);
}

pure Point offset()(Point a, int x, int y) @safe @nogc nothrow
{
    return Point(a.x + x, a.y + y);
}

pure Rectangle offset()(Rectangle a, int x, int y) @safe @nogc nothrow
{
    return Rectangle(a.x + x, a.y + y, a.w, a.h);
}

pure float distance(T)(T a, T b) @safe @nogc nothrow
    if (is(T : Point) || is(T : Rectangle))
{
    float dx = abs(a.x - b.x);
    float dy = abs(a.y - b.y);

    return sqrt(dx * dx + dy * dy);
}

pure long intersectionArea()(Rectangle a, Rectangle b) @safe @nogc nothrow
{
    auto maxX_a = a.x + a.w;
    auto maxX_b = b.x + b.w;
    auto maxY_a = a.y + a.h;
    auto maxY_b = b.y + b.h;

    long dx = min(maxX_a, maxX_b) - max(a.x, b.x);
    long dy = min(maxY_a, maxY_b) - max(a.y, b.y);

    if (dx >= 0 && dy >= 0) {
        return dx * dy;
    }
    else {
        return -1;
    }
}

mixin template RemovalFlag()
{
    private bool _removeMe;

    void markForRemoval() pure @safe @nogc nothrow
    {
        _removeMe = true;
    }

    bool isMarkedForRemoval() const pure @safe @nogc nothrow
    {
        return _removeMe;
    }
}

mixin template Observable(string eventName, TList...)
{
    alias ObserverType = void delegate(TList);

    private ObserverType[] observers;

    private void notifyObservers(string event)(TList args) if (event == eventName)
    {
        foreach (observer; observers)
        {
            observer(args);
        }
    }

    void addObserver(string event)(ObserverType observer) @safe nothrow
        if (event == eventName)
    {
        observers ~= observer;
    }

    void removeObserver(string event)(ObserverType observer) @safe nothrow
        if (event == eventName)
    {
        observers = observers.remove!(a => a is observer);
    }
}

unittest
{
    mixin Observable!"foo";

    @nogc nothrow void delegate() d1 = { };
    @nogc nothrow void delegate() d2 = { };

    addObserver!"foo"( d1 );
    addObserver!"foo"( d2 );
    addObserver!"foo"( d1 );

    assert(observers.length == 3);

    removeObserver!"foo"( d1 );

    assert(observers.length == 1);
    assert(observers[0] is d2);
}

template ifPresent(alias functn)
{
    void ifPresent(T)(auto ref T t)
        if (isInstanceOf!(Nullable, T) && is(typeof( unaryFun!functn(T.init.get) )))
    {
        if ( ! t.isNull )
        {
            functn(t.get);
        }
    }
}

bool isNotNull(T)(auto ref T t) if (isInstanceOf!(Nullable, T))
{
    return ! t.isNull;
}

@trusted auto asDelegate(T)(auto ref T t) if (isCallable!T)
{
    return toDelegate(t);
}

final class IOException : Exception
{
    this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, file, line);
    }
}

version (server) {} else:

void drawBorder(ref Renderer renderer,
                int width,
                int height,
                int borderWidth,
                Point position,
                ubyte r, ubyte g, ubyte b) @safe @nogc nothrow
{
    renderer.setDrawColor(r, g, b);
    renderer.fillRectangle(Rectangle(position.x - borderWidth, position.y - borderWidth,
                                     borderWidth, height + borderWidth*2));
    renderer.fillRectangle(Rectangle(position.x - borderWidth, position.y - borderWidth,
                                     width + borderWidth*2, borderWidth));
    renderer.fillRectangle(Rectangle(position.x + width, position.y - borderWidth,
                                     borderWidth, height + borderWidth*2));
    renderer.fillRectangle(Rectangle(position.x - borderWidth, position.y + height,
                                     width + borderWidth*2, borderWidth));
}

void drawBorder(T)(ref Renderer renderer,
                   int width,
                   int height,
                   int borderWidth,
                   Point position,
                   T color) @safe @nogc nothrow
{
    pragma(inline, true);
    drawBorder(renderer, width, height, borderWidth, position, cast(ubyte) color[0],
                                                               cast(ubyte) color[1],
                                                               cast(ubyte) color[2]);

}

interface Clickable
{
    @safe void mouseMoved(Point p);
    @safe void mouseButtonDown(Point p);
    @safe void mouseButtonUp(Point p);
}

mixin template MouseDownActivation()
{
    private
    {
        Rectangle box;
        void delegate() @safe clickHandler;
        bool isEnabled;
        bool beingClicked;
    }

    void onClick(void delegate() @safe fn) @property pure nothrow @nogc
    {
        this.clickHandler = fn;
    }

    void enabled(bool value) @property pure nothrow @nogc
    {
        isEnabled = value;

        if (value == false) {
            beingClicked = false;
        }
    }

    bool enabled() @property const pure nothrow @nogc
    {
        return isEnabled;
    }

    void setRectangle(Rectangle box) pure nothrow @nogc
    {
        this.box = box;
    }

    void mouseMoved(Point position) pure nothrow @nogc
    {
    }

    void mouseButtonDown(Point position)
    {
        if ( isEnabled && box.containsPoint(position) ) {
            beingClicked = true;
            clickHandler();
        }
    }

    void mouseButtonUp(Point position)
    {
        beingClicked = false;
    }

    bool shouldBeHighlighted() const pure nothrow @nogc
    {
        return beingClicked;
    }
}

mixin template MouseUpActivation()
{
    private
    {
        Rectangle box;
        Point lastMousePosition;
        void delegate() @safe clickHandler;
        bool isEnabled;
        bool beingClicked;
        bool mouseDown;
    }

@safe:

    void onClick(void delegate() @safe fn) @property pure nothrow @nogc
    {
        this.clickHandler = fn;
    }

    void enabled(bool value) @property pure nothrow @nogc
    {
        isEnabled = value;
    }

    bool enabled() @property const pure nothrow @nogc
    {
        return isEnabled;
    }

    void setRectangle(Rectangle box) pure nothrow @nogc
    {
        this.box = box;
    }

    void mouseMoved(Point position) pure nothrow @nogc
    {
        this.lastMousePosition = position;
    }

    void mouseButtonDown(Point position) pure nothrow @nogc
    {
        if (isEnabled == false) {
            return;
        }

        if ( box.containsPoint(position) ) {
            beingClicked = true;
        }

        mouseDown = true;
    }

    void mouseButtonUp(Point position)
    {
        if ( isEnabled && mouseDown && beingClicked && box.containsPoint(position) )
        {
            clickHandler();
        }

        mouseDown = false;
        beingClicked = false;
    }

    bool shouldBeHighlighted() const pure nothrow @nogc
    {
        version (Android) {
            return isEnabled && mouseDown && beingClicked;
        }
        else {
            return isEnabled && ((mouseDown && beingClicked)
                    || (!mouseDown && box.containsPoint(lastMousePosition)));
        }
    }
}

interface Focusable
{
@safe:

    bool focusEnabled();
    void receiveFocus();
    void receiveFocusFrom(Focusable f);
    void windowFocusNotify(FocusType type);
    void loseFocus();
    Focusable nextUp();
    Focusable nextLeft();
    Focusable nextRight();
    Focusable nextDown();
    Focusable nextTab();
    void cursorMoved();
    void activate();
}

enum FocusType
{
    NONE,
    WEAK,
    STRONG
}

mixin template BasicFocusable()
{
    private FocusType focusType;
    private FocusType windowFocusType;

    void receiveFocus()
    {
        focusType = FocusType.STRONG;
    }

    void receiveFocusFrom(Focusable f)
    {
        receiveFocus();
    }

    void loseFocus()
    {
        focusType = FocusType.NONE;
    }

    void windowFocusNotify(FocusType type)
    {
        windowFocusType = type;
    }

    void cursorMoved()
    {
        if (focusType == FocusType.STRONG) {
            focusType = FocusType.WEAK;
        }
    }

    void activate()
    {
        clickHandler();

        version (Android) { } else {
            mouseDown = false;
        }
        beingClicked = false;
    }

}

mixin template ConfigFocusable()
{
    private
    {
        Focusable above;
        Focusable below;
        Focusable left;
        Focusable right;
        Focusable tabNext;
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

    Focusable nextUp() @property //stfu
    {
        return above !is null && above.focusEnabled ? above : this;
    }

    Focusable nextDown() @property //stfu
    {
        return below !is null && below.focusEnabled ? below : this;
    }

    Focusable nextLeft() @property //stfu
    {
        return left !is null && left.focusEnabled ? left : this;
    }

    Focusable nextRight() @property //stfu
    {
        return right !is null && right.focusEnabled ? right : this;
    }

    Focusable nextTab() @property //stfu
    {
        if (tabNext is null) {
            return this;
        }
        else {
            return tabNext.focusEnabled ? tabNext : tabNext.nextTab();
        }
    }
}

