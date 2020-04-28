module gamemodel;
@safe:

import std.typecons : Nullable, nullable;
import std.algorithm : each, remove, count, all;
import std.exception : enforce;
import std.conv : to;

import player;
import card;
import util;
import playergrid;
import net : ServerPlayer;

enum GameState
{
    NOT_STARTED,
    DEALING,
    FLIP_CHOICE,
    PLAYER_TURN,
    BETWEEN_HANDS,
    END_GAME
}

struct GameModel
{
    private
    {
        Player[ubyte] players;
        DiscardStack discardPile = new DiscardStack();
        ubyte playerCurrentTurn;
        Nullable!ubyte playerOut;
        int handNumber = 1;
    }

    @disable this(this);

    ubyte getNextPlayerAfter(ubyte playerKey) const pure nothrow
    {
        int loopCount = 0;

        do
        {
            ++playerKey;
            ++loopCount;

            if (loopCount > 256) {
                throw new Error("no players");
            }
        }
        while (!(playerKey in players));

        assert(playerKey in players);

        return playerKey;
    }

    unittest
    {
        GameModel model;
        model.playerCurrentTurn = 255;

        model.addPlayer(new ClientPlayer());
        model.setPlayer(new ClientPlayer(), 2);
        model.setPlayer(new ClientPlayer(), 5);

        model.nextPlayerTurn();
        assert(model.playerCurrentTurn == 0);
        model.nextPlayerTurn();
        assert(model.playerCurrentTurn == 2);
        model.nextPlayerTurn();
        assert(model.playerCurrentTurn == 5);
        model.nextPlayerTurn();
        assert(model.playerCurrentTurn == 0);
    }

    void pushToDiscard(Card c) pure
    {
        discardPile.push(c);
    }

    Nullable!(const(Card)) getDiscardTopCard() const pure nothrow
    {
        return discardPile.topCard();
    }

    ubyte addPlayer(Player p) pure nothrow
    {
        foreach (ubyte n; 0 .. 256)
        {
            if (n !in players)
            {
                players[n] = p;
                return n;
            }
        }

        throw new Error("no unused keys");
    }

    void setPlayer(Player p, ubyte number) pure nothrow
    {
        if (p is null) {
            players.remove(number);
        }
        else {
            players[number] = p;
        }
    }

    Player getPlayer(ubyte number) pure
    {
        enforce!Error(number in players, "a player with that number doesn't exist");

        return players[number];
    }

    size_t numberOfPlayers() const pure nothrow
    {
        return players.length;
    }

    int playerNumberOf(Player p)
    {
        foreach (ubyte n; 0 .. 256)
        {
            if (players[n] is p) {
                return n;
            }
        }

        return -1;
    }

    int maxPlayerKey() pure nothrow
    {
        foreach_reverse (ubyte n; 0 .. 256)
        {
            if (n in players)
            {
                return n;
            }
        }

        return -1;
    }

    unittest
    {
        GameModel model;

        assert(model.maxPlayerKey() == -1);

        model.addPlayer(new ClientPlayer());
        assert(model.maxPlayerKey() == 0);
        model.setPlayer(new ClientPlayer(), 3);
        assert(model.maxPlayerKey() == 3);
        model.setPlayer(new ClientPlayer(), 255);
        assert(model.maxPlayerKey() == 255);
    }

    auto playerKeys() pure nothrow
    {
        return players.byKey();
    }

    Nullable!Player playerWhoseTurnItIs() pure nothrow
    {
        if (playerCurrentTurn in players) {
            return players[playerCurrentTurn].nullable;
        }
        else {
            return (Nullable!Player).init;
        }
    }

    void setPlayerCurrentTurn(ubyte player) pure nothrow
    {
        playerCurrentTurn = player;
    }

    void setPlayerOut(ubyte playerNum) pure nothrow
    {
        playerOut = playerNum;
    }

    Nullable!ubyte getPlayerOut() pure nothrow
    {
        return playerOut;
    }

    void incrementHandNumber() pure nothrow
    {
        ++handNumber;
    }

    int getHandNumber() pure nothrow
    {
        return handNumber;
    }
}

struct ServerGameModel
{
    alias baseModel this;

    private GameModel baseModel;
    private GameState currentState = GameState.NOT_STARTED;
    private Deck deck = new Deck();
    private Card drawnCard;
    private Observer[] observers;
    private ubyte dealer = 0;
    private ubyte playerFirstTurn;

    ubyte addPlayer(Player p, Observer o)
    {
        assert(currentState == GameState.NOT_STARTED);

        ubyte n = baseModel.addPlayer(p);
        observers.each!( obs => obs.playerJoined(n, p.getName()) );
        observers ~= o;

        return n;
    }

    size_t numberOfPlayers()
    {
        return baseModel.numberOfPlayers();
    }

    int getCurrentPlayerTurn()
    {
        return playerCurrentTurn;
    }

    Player playerWhoseTurnItIs() pure nothrow
    {
        auto result = baseModel.playerWhoseTurnItIs();

        if (result.isNotNull) {
            return result.get;
        }
        else {
            throw new Error("invalid state");
        }
    }

    ubyte getDealer()
    {
        return dealer;
    }

    int playerNumberOf(Player p)
    {
        return baseModel.playerNumberOf(p);
    }

    auto playerKeys() pure nothrow
    {
        return baseModel.playerKeys();
    }

    Player opIndex(ubyte index) pure
    {
        return baseModel.getPlayer(index);
    }

    GameState getState() const pure nothrow
    {
        return currentState;
    }

    bool hasDrawnCard() const pure nothrow
    {
        return drawnCard !is null;
    }

    Nullable!(const(Card)) getDrawnCard() const pure nothrow
    {
        if (drawnCard !is null) {
            return drawnCard.nullable;
        }
        else {
            return (Nullable!(const(Card))).init;
        }
    }

    Nullable!(const(Card)) getDiscardTopCard() const pure nothrow
    {
        return baseModel.getDiscardTopCard();
    }

    void deal()
    {
        assert(currentState == GameState.NOT_STARTED
                || currentState == GameState.BETWEEN_HANDS
                || currentState == GameState.END_GAME);

        if (handNumber != 1 || dealer !in players) {
            dealer = getNextPlayerAfter(dealer);
        }

        currentState = GameState.DEALING;
        observers.each!( obs => obs.deal(dealer) );

        foreach (p; players.byValue)
        {
            (cast(ServerPlayer) p).setGrid( new PlayerGrid() );
        }

        enforce!Error(deck.size > numberOfPlayers() * 12, "deck doesn't have enough cards");

        foreach (n; 0 .. 12)
        {
            ubyte num = baseModel.getNextPlayerAfter(cast(ubyte) dealer);
            ubyte first = num;

            do
            {
                Card c = deck.randomCard().get;
                players[num].getGrid.add(c);
                num = baseModel.getNextPlayerAfter(num);
            }
            while (num != first);
        }
    }

    void beginFlipChoices()
    {
        assert(currentState == GameState.DEALING);

        currentState = GameState.FLIP_CHOICE;
        observers.each!( obs => obs.chooseFlip() );
    }

    void beginTurn(bool firstTurn = false)()
    {
        static if (firstTurn)
        {
            assert(currentState == GameState.FLIP_CHOICE);

            currentState = GameState.PLAYER_TURN;

            Nullable!Card flip = deck.randomCard();
            enforce!Error(flip.isNotNull, "randomCard() returned null Nullable!Card");
            discardPile.push(flip.get);
            observers.each!( obs => obs.discardFlippedOver(flip.get.rank) );
        }
        else
        {
            playerCurrentTurn = getNextPlayerAfter(playerCurrentTurn);
        }
        assert(currentState == GameState.PLAYER_TURN);
        assert(drawnCard is null);

        forEachOtherObserver!( obs => obs.changeTurn(playerCurrentTurn) );
        (cast(ServerPlayer) players[playerCurrentTurn]).observer().yourTurn();
    }

    // Draws a card for the current player and returns it. Other clients/observers are notified.
    // Caller is responsible for sending the card value to the client
    // (never returns null)
    Card drawCard()
    {
        assert(currentState == GameState.PLAYER_TURN);
        assert(drawnCard is null);

        drawnCard = deck.randomCard().get;  // TODO recycle discards to the deck if empty
        forEachOtherObserver!( obs => obs.drawpile(playerCurrentTurn) );
        return drawnCard;
    }

    void exchangeDrawnCard(int row, int col)
    {
        enforce!Error(drawnCard !is null, "Illegal operation: drawnCard is null");
        enforce!Error(players[playerCurrentTurn][row, col].isNotNull, "Illegal operation: card doesn't exist");
        assert(currentState == GameState.PLAYER_TURN);

        Card discarding = players[playerCurrentTurn][row, col].get;
        discarding.revealed = true;
        discardPile.push(discarding);
        players[playerCurrentTurn][row, col] = drawnCard;
        drawnCard.revealed = true;
        scope (exit) {
            drawnCard = null;
            checkColumnEquality(col);
        }

        foreach (obs; observers) {
            obs.drawpilePlace(playerCurrentTurn, row, col, drawnCard.rank, discarding.rank);
        }
    }

    void discardDrawnCard()
    {
        enforce!Error(drawnCard !is null, "Illegal operation: drawnCard is null");
        assert(currentState == GameState.PLAYER_TURN);

        discardPile.push(drawnCard);
        drawnCard.revealed = true;
        scope (exit) {
            drawnCard = null;
        }

        forEachOtherObserver!( obs => obs.drawpileReject(playerCurrentTurn, drawnCard.rank) );
    }

    void takeDiscardCard(int row, int col)
    {
        enforce!Error(discardPile.topCard.isNotNull, "Illegal operation: discard pile is empty");
        enforce!Error(players[playerCurrentTurn][row, col].isNotNull, "Illegal operation: card doesn't exist");
        assert(currentState == GameState.PLAYER_TURN);

        Card discarding = players[playerCurrentTurn][row, col].get;
        Card taken = discardPile.pop().get;
        players[playerCurrentTurn][row, col] = taken;
        discardPile.push(discarding);
        discarding.revealed = true;
        scope (exit) {
            checkColumnEquality(col);
        }

        foreach (obs; observers) {
            obs.discardSwap(playerCurrentTurn, row, col, taken.rank, discarding.rank);
        }
    }

    void flipCard(int row, int col)
    {
        enforce!Error(players[playerCurrentTurn][row, col].isNotNull, "Illegal operation: card doesn't exist");
        assert(! players[playerCurrentTurn][row, col].get.revealed);
        assert(currentState == GameState.PLAYER_TURN);

        Card card = players[playerCurrentTurn][row, col].get;
        card.revealed = true;
        scope (exit) {
            checkColumnEquality(col);
        }

        observers.each!( obs => obs.revealed(playerCurrentTurn, row, col, card.rank) );
    }

    void flipCard(Player player, int row, int col)
    {
        enforce!Error(player[row, col].isNotNull, "Illegal operation: card doesn't exist");
        assert(player[row, col].get.revealed == false);
        assert(currentState == GameState.FLIP_CHOICE);
        assert(player.getGrid.getCardsAsRange.count!(a => a.revealed) < 2);

        Card card = player[row, col].get;
        card.revealed = true;
        observers.each!( obs => obs.revealed(playerNumberOf(player), row, col, card.rank) );

        checkIfShouldBeginFirstTurn();
    }

    void playerLeft(Player p)
    {
        foreach (keyValue; players.byKeyValue)
        {
            if (p is keyValue.value)
            {
                observers.each!( obs => obs.playerLeft(keyValue.key) );

                bool result = players.remove(keyValue.key);
                assert(result);

                if (currentState != GameState.NOT_STARTED && currentState != GameState.END_GAME
                    && currentState != GameState.BETWEEN_HANDS)
                {
                    enforce!Error(p.hasGrid, "expected Player to have a PlayerGrid");

                    discardPile.bury( p.getGrid().getCardsAsRange() );
                    p.getGrid().clear();
                }

                if (currentState == GameState.PLAYER_TURN && keyValue.key == playerCurrentTurn)
                {
                    beginTurn();
                }
                return;
            }
        }

        throw new Error("no such player in GameModel");
    }

    void waitForReconnect(Player p)
    {
        foreach (keyValue; players.byKeyValue)
        {
            if (p is keyValue.value) {
                observers.each!( obs => obs.waiting(keyValue.key) );
                return;
            }
        }

        throw new Error("no such player in GameModel");
    }

    void playerReconnected(Player p)
    {
        foreach (keyValue; players.byKeyValue)
        {
            if (p is keyValue.value) {
                observers.each!( obs => obs.reconnected(keyValue.key) );
                return;
            }
        }

        throw new Error("no such player in GameModel");
    }

    void allPlayersReconnected() pure nothrow
    {
        // TODO
    }

    void addObserver(Observer obs) pure nothrow
    {
        observers ~= obs;
    }

    void removeObserver(Observer obs) pure nothrow
    {
        observers = observers.remove!(a => a is obs);
    }

    interface Observer
    {
        Player player();
        void deal(int dealer);
        void discardFlippedOver(int card);
        void chooseFlip();
        void changeTurn(int playerNum);
        void yourTurn();
        void drawpile(int playerNum);
        void drawpilePlace(int playerNum, int row, int col, int card, int discard);
        void drawpileReject(int playerNum, int card);
        void revealed(int playerNum, int row, int col, int card);
        void discardSwap(int playerNum, int row, int col, int taken, int thrown);
        void columnRemoved(int playerNum, int columnIndex);
        void lastTurn(int playerNum);
        void playerJoined(int number, string name);
        void playerLeft(int playerNum);
        void waiting(int playerNum);
        void reconnected(int playerNum);
        void currentScores(int[int] scores);
        void winner(int playerNum);
    }

    private void checkIfShouldBeginFirstTurn()
    {
        if ( players.byValue.all!(p => p.getGrid.getCardsAsRange.count!(c => c.revealed) == 2) )
        {
            if (handNumber == 1)
            {
                Player maxPlayer;
                int max = int.min;

                foreach (p; players.byValue)
                {
                    int val = p.getGrid.totalRevealedValue;

                    if (val > max) {
                        maxPlayer = p;
                        max = val;
                    }
                }
                assert(maxPlayer !is null);
                assert(max != int.min);

                playerFirstTurn = cast(ubyte) playerNumberOf(maxPlayer);
            }
            else
            {
                playerFirstTurn = getNextPlayerAfter(playerFirstTurn);
            }
            playerCurrentTurn = playerFirstTurn;
            beginTurn!true();
        }
    }

    private void checkColumnEquality(int col)
    {
        Player p = players[playerCurrentTurn];

        enforce!Error(p[0, col].isNotNull);
        enforce!Error(p[1, col].isNotNull);
        enforce!Error(p[2, col].isNotNull);

        Card x = p[0, col].get;
        Card y = p[1, col].get;
        Card z = p[2, col].get;

        if (x.revealed && y.revealed && z.revealed
                && x.rank == y.rank && y.rank == z.rank)
        {
            discardPile.push(x);
            discardPile.push(y);
            discardPile.push(z);

            p[0, col] = null;
            p[1, col] = null;
            p[2, col] = null;

            observers.each!( obs => obs.columnRemoved(playerCurrentTurn, col) );
        }
    }

    private void forEachOtherObserver(alias fn)()
    {
        foreach (obs; observers)
        {
            if (obs.player !is players[playerCurrentTurn]) {
                fn(obs);
            }
        }
    }
}
