module animation;
@safe:

import core.time;

import sdl2.sdl;
import sdl2.texture;
import sdl2.renderer;
import sdl2.mixer;

import card;
import util : lerp, offset;
import playergrid : AbstractClientGrid, card_large_height, card_large_width;

struct MoveAnimation
{
    private
    {
        Card card;
        Rectangle start;
        Rectangle end;
        MonoTime startTime;
        Duration duration;
        public void delegate() _onFinished;
        bool onFinishedCalled;
    }

    this(Card card, Rectangle start, Rectangle end, Duration duration) nothrow
    {
        this.card = card;
        this.start = start;
        this.end = end;
        this.duration = duration;
        this.onFinishedCalled = false;

        startTime = MonoTime.currTime();
    }

    bool process()
    {
        if (card is null) {
            return true;
        }

        Duration elapsed = MonoTime.currTime() - startTime;

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

    bool isFinished()
    {
        Duration elapsed = MonoTime.currTime() - startTime;
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

        Duration elapsed = MonoTime.currTime() - startTime;
        float fraction = elapsed.total!"msecs" / (cast(float) duration.total!"msecs");

        if (fraction > 1.0f) {
            //fraction = 1.0f;
            return;
        }

        Point startCenter = Point(start.x + start.w / 2, start.y + start.h / 2);
        Point endCenter = Point(end.x + end.w / 2, end.y + end.h / 2);

        Point center = lerp(startCenter, endCenter, fraction);

        float width = start.w == end.w ? end.w : lerp(start.w, end.w, fraction);
        float height = start.h == end.h ? end.h : lerp(start.h, end.h, fraction);

        int x = cast(int) (center.x - width / 2.0f);
        int y = cast(int) (center.y - height / 2.0f);

        card.draw(renderer, Point(x, y), cast(int) width, cast(int) height);
    }
}

final class DealAnimation
{
    private
    {
        MoveAnimation animation;
        AbstractClientGrid[] grids;
        Sound sound;
        int gridIndex = 0;
        int cardCount = 1;
    }

    this(Point start, AbstractClientGrid[] grids, Duration timePerCard, Card card, Sound sound)
    {
        animation = MoveAnimation(card,
                                  Rectangle(start.x, start.y , card_large_width, card_large_height),
                                  grids[0].getCardDestination(),
                                  timePerCard);
        this.grids = grids;
        this.sound = sound;
    }

    bool process()
    {
        if (cardCount >= 13) {
            return true;
        }

        if ( animation.process() )
        {
            sound.play();
            grids[gridIndex].add(new Card(CardRank.UNKNOWN));
            ++gridIndex;

            if (gridIndex >= grids.length)
            {
                ++cardCount;

                if (cardCount >= 13) {
                    return true;
                }
                gridIndex = 0;
            }
            animation.end = grids[gridIndex].getCardDestination();
            animation.startTime = MonoTime.currTime();
            animation.onFinishedCalled = false;
        }

        return false;
    }

    void render(ref Renderer renderer)
    {
        animation.render(renderer);
    }
}