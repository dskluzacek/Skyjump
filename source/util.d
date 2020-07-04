module util;

import std.algorithm : remove;
import std.array : array;
import std.traits;
import std.typecons : Nullable, tuple;
import std.functional : unaryFun, toDelegate;
import sdl2.sdl : Rectangle, Point;

pure float lerp(float value1, float value2, float t) @safe @nogc nothrow
{
	return ((1 - t) * value1) + (t * value2);
}

pure bool containsPoint(Rectangle rect, int x, int y) @safe @nogc nothrow
{
	return ( x >= rect.x && x <= rect.x + rect.w
			&& y >= rect.y && y <= rect.y + rect.h );
}

pure bool containsPoint(Rectangle rect, Point p) @safe @nogc nothrow
{
	return containsPoint(rect, p.x, p.y);
}

pure Point offset(Point a, int x, int y) @safe @nogc nothrow
{
	return Point(a.x + x, a.y + y);
}

pure Point lerp(Point a, Point b, float t) @safe @nogc nothrow
{
	return Point(cast(int) lerp(a.x, b.x, t), cast(int) lerp(a.y, b.y, t));
}

interface Clickable
{
	@safe void mouseMoved(Point p);
	@safe void mouseButtonDown(Point p);
	@safe void mouseButtonUp(Point p);
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
		return isEnabled
			&& ((mouseDown && beingClicked) || (!mouseDown && box.containsPoint(lastMousePosition)));
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
