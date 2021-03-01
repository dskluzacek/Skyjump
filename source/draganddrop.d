module draganddrop;
@safe:

import std.typecons;
import sdl2.sdl;
import playergrid : card_large_width, card_large_height;
import util;

enum card_area = card_large_width * card_large_height;

interface DragAndDropTarget
{
    Rectangle[] getBoxes();
    void drop(Rectangle targetBox);
}

mixin template DragAndDrop()
{
    private
    {
        Rectangle box;
        DragAndDropTarget[] targets;
        Point lastMousePosition;
        Point mouseDownPosition;
        bool mouseDown;
        bool beingDragged;
        bool hasBeenDropped;
        bool isEnabled;
    }

    override void mouseMoved(Point p) pure nothrow @nogc
    {
        if (! hasBeenDropped) {
            this.lastMousePosition = p;
        }

        if (mouseDown && isEnabled && ! hasBeenDropped && distance(mouseDownPosition, p) > 10.0f) {
            beingDragged = true;
        }
        super.mouseMoved(p);
    }

    override void mouseButtonDown(Point p) pure nothrow @nogc
    {
        if ( isEnabled && ! hasBeenDropped && box.containsPoint(p) ) {
            mouseDown = true;
            mouseDownPosition = p;
        }
        super.mouseButtonDown(p);
    }

    override void mouseButtonUp(Point p)
    {
        mouseDown = false;
        super.mouseButtonUp(p);

        if (! beingDragged || ! isEnabled) {
            return;
        }
        beingDragged = false;

        Rectangle draggedBox = box.offset( positionAdjustment()[] );

        foreach (target; targets)
        {
            foreach (targetBox; target.getBoxes)
            {
                float intersect = intersectionArea(draggedBox, targetBox);
                float percent = intersect / card_area;

                if ( (targetBox.containsPoint(p) && percent > 0.5f) || percent > 0.7f ) {
                    hasBeenDropped = true;
                    target.drop(targetBox);
                    return;
                }
            }
        }
    }

    Tuple!(int, int) positionAdjustment()
    {
        return tuple(lastMousePosition.x - mouseDownPosition.x, lastMousePosition.y - mouseDownPosition.y);
    }

    bool isBeingDragged()
    {
        return beingDragged;
    }

    bool isDropped()
    {
        return hasBeenDropped;
    }

    override void setRectangle(Rectangle box) pure nothrow @nogc
    {
        this.box = box;
        super.setRectangle(box);
    }

    void setTargets(DragAndDropTarget[] targets)
    {
        this.targets = targets.dup;
        hasBeenDropped = false;
    }

    void reset()
    {
        hasBeenDropped = false;
        beingDragged = false;
        mouseDown = false;
    }

    void dragEnabled(bool value) @property pure nothrow @nogc
    {
        isEnabled = value;

        if (value) {
            hasBeenDropped = false;
        }
    }
}