module util;

import std.algorithm : remove;
import std.array : array;
import std.traits;
import std.typecons : Nullable;
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

interface Clickable
{
	void mouseMoved(Point p);
	void mouseButtonDown(Point p);
	void mouseButtonUp(Point p);
}

mixin template MouseUpActivation()
{
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
