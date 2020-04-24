module playergrid;
@safe:

import std.typecons;
import std.range : chain;
import std.algorithm : filter;

import sdl2.sdl;
import sdl2.texture;
import sdl2.renderer;
import card;
import util;

enum card_large_height  = 240,
     card_large_width   = 172,
     card_medium_height = 132,
     card_medium_width  =  95;

immutable large_row_coord = [0, 250, 500];
immutable large_col_coord = [0, 192, 384, 576];

immutable med_row_coord = [0, 138, 276];
immutable med_col_coord = [0, 105, 210, 315];

class PlayerGrid
{
    private
    {
        Card[][] cards;
    }

    this() pure nothrow
    {
        cards = new Card[][3];
        cards[0] = new Card[4];
        cards[1] = new Card[4];
        cards[2] = new Card[4];
    }

    final bool add(Card c) pure nothrow @nogc
    {
        foreach (row; 0 .. 3)
        {
            foreach (col; 0 .. 4)
            {
                if (cards[row][col] is null) {
                    cards[row][col] = c;
                    return true;
                }
            }
        }
        return false;
    }

    final Card[][] getCards() pure nothrow @nogc
    {
        return cards;
    }

    final void setCards(Card[][] cards) pure nothrow
    {
        assert(cards.length == 3);
        assert(cards[0].length == 4);
        assert(cards[1].length == 4);
        assert(cards[2].length == 4);

        this.cards = new Card[][3];
        this.cards[0] = cards[0].dup;
        this.cards[1] = cards[1].dup;
        this.cards[2] = cards[2].dup;
    }

    final auto getCardsAsRange() pure nothrow @nogc
    {
        return chain(cards[0], cards[1], cards[2]).filter!( a => a !is null );
    }

    final void clear() pure nothrow @nogc
    {
        foreach (row; 0 .. 3)
        {
            foreach (col; 0 .. 4)
            {
                cards[row][col] = null;
            }
        }
    }

    unittest
    {
        PlayerGrid grid = new PlayerGrid();
        grid.add( new Card(CardRank.THREE) );
        grid.add( new Card(CardRank.ZERO) );
        grid.add( new Card(CardRank.SIX) );
        grid.add( new Card(CardRank.SEVEN) );
        grid.add( new Card(CardRank.FOUR) );
        assert(grid.cards[0][0].value == 3);
        assert(grid.cards[0][1].value == 0);
        assert(grid.cards[0][2].value == 6);
        assert(grid.cards[0][3].value == 7);
        assert(grid.cards[1][0].value == 4);

        foreach (n; 0 .. 7)
        {
            assert(grid.add( new Card(CardRank.NEGATIVE_ONE) ) == true);
        }

        assert(grid.add( new Card() ) == false);
        assert(grid.cards[2][3].value == -1);
    }
}

abstract class AbstractClientGrid : PlayerGrid
{
    private Point position;

    this(Point position) pure nothrow
    {
        this.position = position;
    }

    this() pure nothrow
    {
        super();
    }

    final void setPosition(Point position) pure nothrow
    {
        this.position = position;
    }

    final Point getPosition() const pure nothrow
    {
        return position;
    }

    abstract Point getCardDestination();
    abstract void render(ref Renderer r);
}

class ClientPlayerGrid
    (int card_w = card_medium_width, int card_h = card_medium_height,
     int[] r_coord = med_row_coord, int[] c_coord = med_col_coord) : AbstractClientGrid
{
    this(Point position) pure nothrow
    {
        super(position);
    }

    this() pure nothrow
    {
        super();
    }

    override Point getCardDestination() const pure nothrow @nogc
    {
        enum int x = (med_col_coord[1] + card_medium_width + med_col_coord[2]) / 2 - (card_large_width / 2);
        enum int y = med_row_coord[1] + (card_medium_height / 2) - (card_large_height / 2);

        return position.offset(x, y);
    }

    override final void render(ref Renderer renderer)
    {
        foreach (row; 0 .. 3)
        {
            foreach (col; 0 .. 4)
            {
                drawCard(cards[row][col], false, row, col, renderer);
            }
        }
    }

    void drawCard(Card c, bool highlight, int row, int col, ref Renderer renderer)
    {
        if (c is null) {
            return;
        }

        c.draw(renderer,
            position.offset(c_coord[col], r_coord[row]), card_w, card_h, highlight);
    }
}

final class ClickablePlayerGrid :
    ClientPlayerGrid!(card_large_width, card_large_height, large_row_coord, large_col_coord), Clickable
{
    private
    {
        HighlightingMode mode = HighlightingMode.OFF;
        Nullable!Card cardBeingClicked;
        void delegate(int, int) clickHandler;
        Point lastMousePosition;
        bool mouseDown;
    }

    enum HighlightingMode
    {
        OFF,
        SELECTION,
        PLACEMENT
    }

    this(Point position) pure nothrow
    {
        super(position);
    }

    override void mouseMoved(Point position) pure nothrow @nogc
    {
        this.lastMousePosition = position;
    }

    override void mouseButtonDown(Point position) pure nothrow
    {
        cardBeingClicked = getCardByMousePosition(position);
        mouseDown = true;
    }

    override void mouseButtonUp(Point position)
    {
        auto coords = getRowAndColumn(position);

        if (coords.isNotNull)
        {
            Card cardHovered = cards[coords.get.row][coords.get.col];

            if (mouseDown && cardBeingClicked.isNotNull
            && cardHovered !is null && cardHovered is cardBeingClicked.get)
            {
                clickHandler(coords.get[]);
            }
        }

        mouseDown = false;
    }

    Nullable!Card getCardByMousePosition(Point mouse) pure nothrow
    {
        auto result = getRowAndColumn(mouse);

        if (result.isNotNull) {
            return (cards[result.get.row][result.get.col]).nullable;
        }
        else {
            return (Nullable!Card).init;
        }
    }

    void setHighlightingMode(HighlightingMode m) pure nothrow @nogc
    {
        this.mode = m;
    }

    void setClickHandler(void delegate(int, int) @safe handler) pure nothrow @nogc
    {
        this.clickHandler = handler;
    }

    override Point getCardDestination() const pure nothrow @nogc
    {
        foreach (row; 0 .. 3)
        {
            foreach (col; 0 .. 4)
            {
                if (cards[row][col] is null)
                {
                    return position.offset(large_col_coord[col], large_row_coord[row]);
                }
            }
        }

        return Point.init;
    }

    override void drawCard(Card c, bool highlight, int row, int col, ref Renderer renderer)
    {
        bool shouldHighlight = false;

        if (mode == HighlightingMode.SELECTION)
        {
            if ( (mouseDown && cardBeingClicked.isNotNull && cardBeingClicked.get is c)
                || (!mouseDown && getBox(row, col).containsPoint(lastMousePosition)) )
            {
                shouldHighlight = true;
            }
        }

        super.drawCard(c, shouldHighlight, row, col, renderer);
    }

    private auto getRowAndColumn(Point mouse) const pure nothrow @nogc
    {
        foreach (row; 0 .. 3)
        {
            foreach (col; 0 .. 4)
            {
                auto box = getBox(row, col);

                if ( box.containsPoint(mouse) )
                {
                    if (cards[row][col] !is null) {
                        return tuple!("row", "col")(row, col).nullable;
                    }
                    else {
                        return (Nullable!(Tuple!(int, "row", int, "col"))).init;
                    }
                }
            }
        }

        return (Nullable!(Tuple!(int, "row", int, "col"))).init;
    }

    private Rectangle getBox(int row, int col) const pure nothrow @nogc
    {
        return Rectangle(position.x + large_col_coord[col],
                         position.y + large_row_coord[row],
                         card_large_width,
                         card_large_height);
    }
}
