module player;
@safe:

import std.typecons;

import playergrid;
import card : Card;
import std.exception : enforce;

alias LocalPlayer  = PlayerImpl!ClickablePlayerGrid;
alias ClientPlayer = PlayerImpl!AbstractClientGrid;

interface Player
{
    string getName();
    void setName(in char[] name);
    PlayerGrid getGrid();
    bool hasGrid();
    int getScore();
    void addScore(int amount);
    Nullable!Card opIndex(uint row, uint col);
    void opIndexAssign(Card c, uint row, uint col);
    void reset();
}

class PlayerImpl(GridType) : Player
{
    private
    {
        string name = "";
        GridType grid;
        int score;
    }

    this()
    {
    }

    this(in char[] name)
    {
        this.name = name.idup;
    }

    override string getName()
    {
        enforce!Error(name !is null, "name was null");

        return name;
    }

    override void setName(in char[] name)
    {
        this.name = name.idup;
    }

    override GridType getGrid()
    {
        enforce!Error(grid !is null, "grid was null");

        return grid;
    }

    override bool hasGrid()
    {
        return grid !is null;
    }

    void setGrid(GridType grid)
    {
        this.grid = grid;
    }

    override int getScore()
    {
       return score;
    }

    override void addScore(int amount)
    {
        score += amount;
    }

    override Nullable!Card opIndex(uint row, uint col)
    {
        Card result = grid.getCards()[row][col];

        if (result is null) {
            return (Nullable!Card).init;
        }
        else {
            return nullable(result);
        }
    }

    override void opIndexAssign(Card c, uint row, uint col)
    {
        grid.getCards()[row][col] = c;
    }

    override void reset()
    {
        name = "";
        grid.clear();
        score = 0;
    }
}
