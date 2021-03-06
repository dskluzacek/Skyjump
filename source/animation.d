/*
 * animation.d
 * 
 * Copyright (c) 2021 David P Skluzacek
 */

module animation;
@safe:

import core.time;

import sdl2.sdl;
import sdl2.texture;
import sdl2.renderer;
import sdl2.mixer;

import card;
import util : lerp, offset, distance;
import playergrid : AbstractClientGrid, card_large_height, card_large_width;

alias StartTimeType = MonoTime;
alias DurationType = Duration;

struct MoveAnimation
{
    private
    {
        Card card;
        Rectangle start;
        Rectangle end;
        StartTimeType startTime;
        DurationType duration;
        public void delegate() _onFinished;
        bool onFinishedCalled;

        version (Android) {
            int prevX = -1;
            int prevY = -1;
        }
    }

    this(Card card, Rectangle start, Rectangle end, Duration duration) nothrow @nogc
    {
        this.card = card;
        this.start = start;
        this.end = end;
        this.duration = duration;
        this.onFinishedCalled = false;
        
        startTime = MonoTime.currTime();
    }

    this(Card card, Rectangle start, Rectangle end, float speed) nothrow @nogc
    {
        auto dur = speedToDuration(speed, start, end);
        this(card, start, end, dur);
    }

    this(Card card, Rectangle start, Rectangle end, float speed, Duration minDuration) nothrow @nogc
    {
        auto dur = speedToDuration(speed, start, end);

        if (minDuration > dur) {
            dur = minDuration;
        }
        this(card, start, end, dur);
    }

    private static pure Duration speedToDuration(float speed, Rectangle start, Rectangle end) nothrow @nogc
    {
        Point startCenter = Point(start.x + start.w / 2, start.y + start.h / 2);
        Point endCenter = Point(end.x + end.w / 2, end.y + end.h / 2);
        
        return (cast(long) (distance(startCenter, endCenter) / speed)).msecs;
    }
    
    bool process()
    {
        if (card is null) {
            return true;
        }

        auto elapsed = getElapsedTime();

        if (elapsed.total!"msecs" >= duration.total!"msecs")
        {
            if (_onFinished && !onFinishedCalled) {
                onFinishedCalled = true;
                _onFinished();
            }
            return true;
        }
        else
        {
            return false;
        }
    }

    void cancel()
    {
        startTime = StartTimeType.init;
        card = null;
    }

    bool isFinished()
    {
        if (startTime == StartTimeType.init) {
            return true;
        }

        auto elapsed = getElapsedTime();
        return elapsed.total!"msecs" >= duration.total!"msecs";
    }

    void onFinished(void delegate() @safe fn) @property
    {
        this._onFinished = fn;
    }

    void render(ref Renderer renderer)
    {
        if (card is null) {
            return;
        }

        auto elapsed = getElapsedTime();
        float fraction = elapsed.total!"usecs" / (cast(float) duration.total!"usecs");

        if (fraction > 1.1f) {
            return;
        }
        else if (fraction > 1.0f) {
            fraction = 1.0f;
        }

        Point startCenter = Point(start.x + start.w / 2, start.y + start.h / 2);
        Point endCenter = Point(end.x + end.w / 2, end.y + end.h / 2);

        Point center = lerp(startCenter, endCenter, fraction);

        float width = start.w == end.w ? end.w : lerp(start.w, end.w, fraction);
        float height = start.h == end.h ? end.h : lerp(start.h, end.h, fraction);

        int x = cast(int) (center.x - width / 2.0f);
        int y = cast(int) (center.y - height / 2.0f);

        card.draw(renderer, Point(x, y), cast(int) width, cast(int) height);
        
        version (Android) {
            if (prevX >= 0 && prevY >= 0 && fraction < 1.0f) {
                card.draw(renderer, Point(prevX, prevY), cast(int) width, cast(int) height);
            }
            prevX = x;
            prevY = y;
        }
    }

    private DurationType getElapsedTime() @trusted
    {
        return MonoTime.currTime() - startTime;
    }
}

final class DealAnimation
{
    enum number_of_cards = 12;
    
    private
    {
        MoveAnimation[] animations;
        AbstractClientGrid[] grids;
        Sound sound;
        int cardCount = 1;
    }

    this(Point start, AbstractClientGrid[] grids, Duration timePerCard, Card card, Sound sound)  
    {
        this.grids = grids;
        this.sound = sound;
        this.animations = new MoveAnimation[grids.length];

        foreach (i; 0 .. grids.length)
        {
            animations[i] = MoveAnimation(card,
                                Rectangle(start.x, start.y, card_large_width, card_large_height),
                                grids[i].getCardDestination(),
                                timePerCard);
        }
    }

    bool process()
    {
        if (cardCount > number_of_cards) {
            return true;
        }
        bool result;

        foreach (ref anim; animations)
        {
            result = anim.process();
        }

        if (result)
        {
            sound.play();
            
            foreach (grid; grids)
            {
                // use seperate card objects so gui code can use their identity
                grid.add(new Card(CardRank.UNKNOWN));
            }
            ++cardCount;

            if (cardCount > number_of_cards) {
                return true;
            }

            foreach (i, ref anim; animations)
            {
                anim.end = grids[i].getCardDestination();
                anim.startTime = MonoTime.currTime();
                anim.onFinishedCalled = false;

                version (Android) {
                    anim.prevX = -1;
                    anim.prevY = -1;
                }
            }
        }

        return false;
    }

    void render(ref Renderer renderer)
    {
        foreach (ref anim; animations)
        {
            anim.render(renderer);
        }
    }
}
