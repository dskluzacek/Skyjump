module gamemodel;
@safe:

import std.typecons;
import std.algorithm : map, each, remove, count, all, sum, minElement;
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

        model.setPlayer(new PlayerImpl!PlayerGrid(), 0);
        model.setPlayer(new PlayerImpl!PlayerGrid(), 2);
        model.setPlayer(new PlayerImpl!PlayerGrid(), 5);

        model.playerCurrentTurn = model.getNextPlayerAfter(model.playerCurrentTurn);
        assert(model.playerCurrentTurn == 0);
        model.playerCurrentTurn = model.getNextPlayerAfter(model.playerCurrentTurn);
        assert(model.playerCurrentTurn == 2);
        model.playerCurrentTurn = model.getNextPlayerAfter(model.playerCurrentTurn);
        assert(model.playerCurrentTurn == 5);
        model.playerCurrentTurn = model.getNextPlayerAfter(model.playerCurrentTurn);
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

    Nullable!(const(Card)) getDiscardSecondCard() const pure nothrow
    {
        return discardPile.peek(1);
    }

    Nullable!(Card) popDiscardTopCard() pure nothrow
    {
        return discardPile.pop();
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
            assert(players[number] !is null);
        }
    }

    alias opIndex = getPlayer;

    Player getPlayer(ubyte number) pure
    {
        enforce!Error(number in players, "a player with that number doesn't exist");
        assert(players[number] !is null);

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

    Nullable!ubyte getPlayerOut() const pure nothrow
    {
        return playerOut;
    }

    void nextHand()
    {
        ++handNumber;
        discardPile = new DiscardStack();
        playerOut = (Nullable!ubyte).init;

        foreach (player; players) {
            player.getGrid.clear();
        }
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
    private ubyte previousPlayerOut;

    ubyte addPlayer(Player p, Observer o)
    {
        assert(currentState == GameState.NOT_STARTED);

        ubyte n = baseModel.addPlayer(p);
        observers.each!( obs => obs.playerJoined(n, p.getName()) );

        if (o !is null) {
            observers ~= o;
        }

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

    Nullable!ubyte getPlayerOut() const pure nothrow
    {
        return baseModel.getPlayerOut();
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

        assert(deck.size > numberOfPlayers() * 12);

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

            assert(flip.isNotNull);

            discardPile.push(flip.get);
            observers.each!( obs => obs.discardFlippedOver(flip.get.rank) );
        }
        else
        {
            playerCurrentTurn = getNextPlayerAfter(playerCurrentTurn);
        }
        assert(currentState == GameState.PLAYER_TURN);
        assert(drawnCard is null);

        if (playerOut.isNotNull && playerCurrentTurn == playerOut.get)
        {
            endHand();
            return;
        }

        forEachOtherObserver!( obs => obs.changeTurn(playerCurrentTurn) );
        (cast(ServerPlayer) players[playerCurrentTurn]).observer().yourTurn();
    }

    void endHand()
    {
        foreach (key, player; players) {
            player.getGrid.getCardsAsRange.each!( card => card.revealed = true );

            if (key != playerOut.get) {
                observers.each!( obs => obs.updateCards(key, player.getGrid) );
            }

            foreach (col; 0 .. 4) {
                checkColumnEquality(col, player);
            }
        }

        calculateScores();
        observers.each!( obs => obs.currentScores(this) );
        currentState = GameState.BETWEEN_HANDS;
    }

    void nextHand()
    {
        assert(currentState == GameState.BETWEEN_HANDS);
        assert(drawnCard is null);

        baseModel.nextHand();
        deck = new Deck();
    }

    void recycleDiscards()
    {
        assert(discardPile.size > 0);

        Card top = discardPile.pop().get;
        Card[] cards = discardPile.getCards().dup;
        discardPile.clear();
        discardPile.push(top);

        foreach (card; cards) {
            card.revealed = false;
        }
        deck.setCards(cards);
    }

    // Draws a card for the current player and returns it. Other clients/observers are notified.
    // Caller is responsible for sending the card value to the client
    // (never returns null)
    Card drawCard()
    {
        assert(currentState == GameState.PLAYER_TURN);
        assert(drawnCard is null);

        auto c = deck.randomCard();

        if (c.isNull) {
            recycleDiscards();
            c = deck.randomCard();
        }

        drawnCard = c.get;
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
            checkColumnEquality(col, players[playerCurrentTurn]);
            checkIsPlayerOut();
            beginTurn();
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
            beginTurn();
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
            checkColumnEquality(col, players[playerCurrentTurn]);
            checkIsPlayerOut();
            beginTurn();
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
            checkColumnEquality(col, players[playerCurrentTurn]);
            checkIsPlayerOut();
            beginTurn();
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
                    assert(p.hasGrid);

                    discardPile.bury( p.getGrid().getCardsAsRange() );
                    p.getGrid().clear();
                }

                if (currentState == GameState.PLAYER_TURN && keyValue.key == playerCurrentTurn)
                {
                    if (drawnCard !is null) {
                        Card c = drawnCard;
                        drawnCard = null;
                        discardPile.push(c);
                        observers.each!( obs => obs.discardFlippedOver(c.rank) );
                    }

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

    void allPlayersReconnected()
    {
        if (currentState == GameState.PLAYER_TURN)
        {
            if (drawnCard is null) {
                (cast(ServerPlayer) players[playerCurrentTurn]).observer().yourTurn();
            }
            else {
                (cast(ServerPlayer) players[playerCurrentTurn]).observer().resumeDraw();
            }

            forEachOtherObserver!( obs => obs.changeTurn(playerCurrentTurn) );
        }
        else if (currentState == GameState.FLIP_CHOICE)
        {
            observers.each!( obs => obs.chooseFlip() );
        }
    }

    void calculateScores()
    {
        auto totals = players.byValue.map!(p => tuple(p, p.getGrid.getCardsAsRange.map!(c => c.value).sum));
        auto minimum = totals.map!(a => a[1]).minElement;

        foreach (t; totals)
        {
            if (t[0] is players[playerOut.get] && t[1] > minimum)
            {
                t[0].addScore(t[1] * 2);
            }
            else
            {
                t[0].addScore(t[1]);
            }
        }
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
        void resumeDraw();
        void updateCards(int playerNum, PlayerGrid grid);
        void currentScores(ref ServerGameModel players);
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

                playerCurrentTurn = cast(ubyte) playerNumberOf(maxPlayer);
            }
            else
            {
                playerCurrentTurn = previousPlayerOut;
            }

            beginTurn!true();
        }
    }

    private void checkColumnEquality(int col, Player p)
    {
        if (p[0, col].isNull) {
            return;
        }

        assert(p[0, col].isNotNull);
        assert(p[1, col].isNotNull);
        assert(p[2, col].isNotNull);

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

    private void checkIsPlayerOut()
    {
        if (playerOut.isNotNull) {
            return;
        }

        Player player = players[playerCurrentTurn];

        foreach (row; 0 .. 3)
        {
            foreach (col; 0 .. 4)
            {
                if (player[row, col].isNotNull && ! player[row, col].get.revealed) {
                    return;
                }
            }
        }

        playerOut = playerCurrentTurn;
        previousPlayerOut = playerCurrentTurn;
        observers.each!( obs => obs.lastTurn(playerCurrentTurn) );
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
