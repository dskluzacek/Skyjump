module player;
@safe:

import std.typecons;

import playergrid;
import card : Card;
import std.exception : enforce;

version (server) {} else {
    alias LocalPlayer = PlayerImpl!ClickablePlayerGrid;
}

interface Player
{
    string getName();
    void setName(in char[] name);
    PlayerGrid getGrid();
    bool hasGrid();
    int getScore();
    void addScore(int amount);
    void setScore(int score);
    Nullable!int getHandScore();
    void setHandScore(Nullable!int value);
    bool isWinner();
    void setWinner(bool value);
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
        Nullable!int handScore;
        bool winner;
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

    override void setScore(int value)
    {
        score = value;
    }

    override Nullable!int getHandScore()
    {
        return handScore;
    }

    override void setHandScore(Nullable!int value)
    {
        handScore = value;
    }

    override bool isWinner()
    {
        return winner;
    }

    override void setWinner(bool value)
    {
        winner = value;
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
        handScore = (Nullable!int).init;
        winner = false;
    }
}
