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
        int width;
        int height;
        Point start;
        Point end;
        MonoTime startTime;
        Duration duration;
        void delegate() _onFinished;
        bool onFinishedCalled = false;
    }

    this(Card card, int width, int height, Point start, Point end, Duration duration) nothrow
    {
        this.card = card;
        this.width = width;
        this.height = height;
        this.start = start;
        this.end = end;
        this.duration = duration;

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
                _onFinished();
                onFinishedCalled = true;
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

        int x = cast(int) lerp(start.x, end.x, fraction);
        int y = cast(int) lerp(start.y, end.y, fraction);

        card.draw(renderer, Point(x, y), width, height);
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
                                  card_large_width,
                                  card_large_height,
                                  start,
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
