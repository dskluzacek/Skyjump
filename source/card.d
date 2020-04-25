module card;
@safe:

import std.random : uniform;
import std.algorithm : remove;
import std.array;
import std.typecons;
import std.exception : enforce;
import std.range : ElementType, isInputRange;

import sdl2.sdl : Point, Rectangle;
import sdl2.texture;
import sdl2.renderer;

enum highlight_yellow = tuple(255, 255, 165);
enum pale_indigo = tuple(162, 165, 198);

enum CardRank : byte
{
    UNKNOWN = -128,
    NEGATIVE_TWO = -2,
    NEGATIVE_ONE = -1,
    ZERO = 0,
    ONE = 1,
    TWO = 2,
    THREE = 3,
    FOUR = 4,
    FIVE = 5,
    SIX = 6,
    SEVEN = 7,
    EIGHT = 8,
    NINE = 9,
    TEN = 10,
    ELEVEN = 11,
    TWELVE = 12
}

final class Card
{
    private immutable CardRank _rank;
    private bool _revealed;

    private static Texture[CardRank] cardTextures;

    this(CardRank rank) pure nothrow
    {
        _rank = rank;
        _revealed = false;
    }

    this() pure nothrow
    {
        this(CardRank.UNKNOWN);
    }

    CardRank rank() const pure nothrow @nogc
    {
        return _rank;
    }

    bool revealed() @property const pure nothrow @nogc
    {
        return _revealed;
    }

    void revealed(bool reveal) @property pure nothrow @nogc
    {
        _revealed = reveal;
    }

    int value() const pure nothrow @nogc
    {
        if (_rank == CardRank.UNKNOWN)
        {
            return 0;
        }
        else
        {
            return cast(int) _rank;
        }
    }

    void draw(ref Renderer renderer, Point position, int width, int height, bool highlight = false) const
    {
        Texture texture;

        if (_revealed) {
            texture = cardTextures[_rank];
        }
        else {
            texture = cardTextures[CardRank.UNKNOWN];
        }

        if (highlight) {
            texture.setColorMod(pale_indigo[]);
        }
        renderer.renderCopy(texture, position.x, position.y, width, height);
        texture.setColorMod(255, 255, 255);

        if (highlight) {
        //    drawBorder(renderer, width, height, position, 255, 0, 255);
        }
    }

    private void drawBorder(ref Renderer renderer,
                            int width,
                            int height,
                            Point position,
                            ubyte r, ubyte g, ubyte b)
    {
        renderer.setDrawColor(r, g, b);
        renderer.fillRectangle(Rectangle(position.x-8, position.y-8, 8, height+16));
        renderer.fillRectangle(Rectangle(position.x-8, position.y-8, width+16, 8));
        renderer.fillRectangle(Rectangle(position.x + width, position.y-8, 8, height+16));
        renderer.fillRectangle(Rectangle(position.x-8, position.y + height, width+16, 8));
    }

    static setTexture(CardRank rank, Texture texture) nothrow
    {
        cardTextures[rank] = texture;
    }
}

unittest
{
    assert(new Card(CardRank.NEGATIVE_TWO).value == -2);
    assert(new Card(CardRank.TWELVE).value == 12);
    assert(new Card(CardRank.UNKNOWN).value == 0);
    assert(new Card(CardRank.ZERO).value == 0);
}

final class Deck
{
    private Card[] cards;

    this() pure nothrow
    {
        foreach (n ; 0 ..  5) { cards ~= new Card(CardRank.NEGATIVE_TWO); }
        foreach (n ; 0 .. 10) { cards ~= new Card(CardRank.NEGATIVE_ONE); }
        foreach (n ; 0 .. 15) { cards ~= new Card(CardRank.ZERO); }
        foreach (n ; 0 .. 10) { cards ~= new Card(CardRank.ONE); }
        foreach (n ; 0 .. 10) { cards ~= new Card(CardRank.TWO); }
        foreach (n ; 0 .. 10) { cards ~= new Card(CardRank.THREE); }
        foreach (n ; 0 .. 10) { cards ~= new Card(CardRank.FOUR); }
        foreach (n ; 0 .. 10) { cards ~= new Card(CardRank.FIVE); }
        foreach (n ; 0 .. 10) { cards ~= new Card(CardRank.SIX); }
        foreach (n ; 0 .. 10) { cards ~= new Card(CardRank.SEVEN); }
        foreach (n ; 0 .. 10) { cards ~= new Card(CardRank.EIGHT); }
        foreach (n ; 0 .. 10) { cards ~= new Card(CardRank.NINE); }
        foreach (n ; 0 .. 10) { cards ~= new Card(CardRank.TEN); }
        foreach (n ; 0 .. 10) { cards ~= new Card(CardRank.ELEVEN); }
        foreach (n ; 0 .. 10) { cards ~= new Card(CardRank.TWELVE); }
    }

    Nullable!Card randomCard()
    {
        if (cards.length == 0) {
            return (Nullable!Card).init;
        }

        ulong index = uniform!"[)"(0, cards.length);
        Card result = cards[index];
        cards = cards.remove(index);

        enforce!Error(result !is null, "result was null");

        return result.nullable;
    }

    void setCards(Card[] cards) pure nothrow
    {
        this.cards = cards;
    }

    auto size() pure nothrow
    {
        return cards.length;
    }

    bool isEmpty() pure nothrow
    {
        return cards.length == 0;
    }
}

unittest
{
    auto deck = new Deck();
    assert(deck.size == 150);
    assert(deck.isEmpty == false);
    deck.setCards( [new Card(CardRank.ONE)] );
    assert(! deck.isEmpty);
    deck.randomCard();
    assert(deck.isEmpty);
}

final class DiscardStack
{
    private Card[] cards;

    void push(Card c) pure
    {
        enforce!Error(c !is null, "card was null");

        c._revealed = true;
        cards ~= c;
    }

    Nullable!(const(Card)) topCard() const pure nothrow
    {
        if (cards.length == 0) {
            return (Nullable!(const(Card))).init;
        }

        return cards[cards.length - 1].nullable;
    }

    Nullable!Card pop() pure nothrow
    {
        if (cards.length == 0) {
            return (Nullable!Card).init;
        }

        Nullable!Card result = cards[$ - 1];
        cards = cards[0 .. $ - 1];
        return result;
    }

    void bury(T)(T someCards) if ( is(ElementType!T == Card) && isInputRange!T )
    {
        auto arr = someCards.array;
        cards = arr ~ cards;
    }

    Card[] getCards() pure nothrow
    {
        return cards;
    }

    auto size() pure nothrow
    {
        return cards.length;
    }
}

unittest
{
    Card eight = new Card(CardRank.EIGHT);
    Card twelve = new Card(CardRank.TWELVE);
    Card minusTwo = new Card(CardRank.NEGATIVE_TWO);

    auto stack = new DiscardStack();
    stack.push(eight);
    assert(stack.topCard.get is eight);
    stack.push(minusTwo);
    assert(stack.topCard.get is minusTwo);
    stack.push(twelve);
    assert(stack.topCard.get is twelve);
    assert(stack.size == 3);
    assert(stack.pop().get is twelve);
    assert(stack.size == 2);
    assert(stack.topCard.get is minusTwo);
    assert(stack.topCard.get.value == -2);
    assert(stack.pop().get is minusTwo);
    assert(stack.pop().get is eight);
    assert(stack.size == 0);
    assert(stack.pop().isNull);
    assert(stack.topCard.isNull);
}
