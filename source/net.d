module net;
@safe:

import std.stdio;
import std.array : join;
import std.string;
import std.socket;
import std.typecons : Nullable, nullable, Tuple;
import std.conv : to;
import std.traits;
import std.exception : enforce;

import util;
import gamemodel;
import player;
import playergrid;
import card;

enum BUFFER_SIZE = 96;

final class ServerPlayer : PlayerImpl!PlayerGrid
{
    ConnectedClient client;

    this(in char[] name, ConnectedClient client)
    {
        super(name);
        this.client = client;
    }

    ServerGameModel.Observer observer() pure nothrow @nogc
    {
        return client;
    }
}

final class ConnectedClient : ServerGameModel.Observer
{
    private
    {
        Socket _socket;
        ServerPlayer _player;
    }
    public
    {
        bool waitingForJoin = true;
        bool readyReceived;
    }

    this(Socket sock)
    {
        _socket = sock;
    }

    mixin RemovalFlag;

    Nullable!ClientMessage poll(SocketSet socketSet)
    {
        static const(char)[] leftoverChars = "";

        //writeln("socket is null? ", _socket is null);

        if ( socketSet.isSet(_socket) )
        {
            char[BUFFER_SIZE] buffer;
            auto dataLength = _socket.receive(buffer[]);

            if (dataLength == Socket.ERROR)
            {
                throw new SocketReadException("receive returned Socket.ERROR", dataLength);
            }
            else if (dataLength == 0)
            {
                throw new SocketReadException("client closed connection", dataLength);
            }
            else
            {
                //writeln("entering handleChars");
                return handleChars!(ClientMessage, parseClientMessage)(leftoverChars, buffer[0 .. dataLength].idup);
            }
        }
        else if (leftoverChars.length > 0)
        {
            return handleChars!(ClientMessage, parseClientMessage)(leftoverChars, "");
        }
        else
        {
            //writeln("returning Nullable.init");
            return (Nullable!ClientMessage).init;
        }
    }

    Socket socket() pure nothrow @nogc
    {
        return _socket;
    }

    ServerPlayer player() @property pure nothrow @nogc
    {
        return _player;
    }

    void player(ServerPlayer p) @property pure nothrow @nogc
    {
        _player = p;
    }

    override void deal(int dealer)
    {
        send(ServerMessageType.DEAL, dealer);
    }

    override void chooseFlip()
    {
        send(ServerMessageType.CHOOSE_FLIP);
    }

    override void discardFlippedOver(int card)
    {
        send(ServerMessageType.DISCARD_CARD, card);
    }

    override void changeTurn(int playerNum)
    {
        send(ServerMessageType.CHANGE_TURN, playerNum);
    }

    override void yourTurn()
    {
        send(ServerMessageType.YOUR_TURN);
    }

    override void drawpile(int playerNum)
    {
        send(ServerMessageType.DRAWPILE, playerNum);
    }

    override void drawpilePlace(int playerNum, int row, int col, int card, int discard)
    {
        send(ServerMessageType.DRAWPILE_PLACE, playerNum, row, col, card, discard);
    }

    override void drawpileReject(int playerNum, int card)
    {
        send(ServerMessageType.DRAWPILE_REJECT, playerNum, card);
    }

    override void revealed(int playerNum, int row, int col, int card)
    {
        send(ServerMessageType.REVEAL, playerNum, row, col, card);
    }

    override void discardSwap(int playerNum, int row, int col, int taken, int thrown)
    {
        send(ServerMessageType.DISCARD_SWAP, playerNum, row, col, taken, thrown);
    }

    override void columnRemoved(int playerNum, int columnIndex)
    {
        send(ServerMessageType.COLUMN_REMOVAL, playerNum, columnIndex);
    }

    override void lastTurn(int playerNum)
    {
        send(ServerMessageType.LAST_TURN, playerNum);
    }

    override void playerJoined(int number, string name)
    {
        send(ServerMessageType.PLAYER_JOIN, number, name);
    }

    override void playerLeft(int playerNum)
    {
        send(ServerMessageType.PLAYER_LEFT, playerNum);
    }

    override void waiting(int playerNum)
    {
        send(ServerMessageType.WAITING, playerNum);
    }

    override void reconnected(int playerNum)
    {
        send(ServerMessageType.RECONNECTED, playerNum);
    }

    override void winner(int playerNum)
    {
        send(ServerMessageType.WINNER, playerNum);
    }

    override void currentScores(int[int] scoreMap)
    {
        assert(0);
    }

    void sendCards(int playerNumber, PlayerGrid grid)
    {
        char[] message = "cards " ~ playerNumber.to!(char[]);
        message.reserve(48);

        const Card[][] cards = grid.getCards();
        //writeln(cards);

        foreach (row; 0 .. 3)
        {
            foreach (col; 0 .. 4)
            {
                auto c = cards[row][col];

                if (c is null) {
                    message ~= " _";
                }
                else if (! c.revealed) {
                    message ~= " ?";
                }
                else {
                    message ~= " " ~ (cast(int) c.rank).to!(char[]);
                }

            }
        }
        _socket.send(message ~ '\n');
    }

    mixin SendMessage!ServerMessageType;
}

mixin template SendMessage(T)
{
    void send(Seq...)(T msgType, Seq args)
    {
        string message = msgType;

        foreach (i, arg; args)
        {
            static assert( ! is(typeof(arg) == CardRank) );
            static assert( ! isInstanceOf!(Tuple, typeof(arg)) );

            message ~= ' ' ~ arg.to!string;
        }
        () @trusted { _socket.send(message ~ '\n'); } ();
    }
} 

final class ConnectionToServer
{
    private Socket _socket;

    this(Socket sock)
    {
        _socket = sock;
    }

    mixin SendMessage!ClientMessageType;

    Nullable!ServerMessage poll(SocketSet socketSet)
    {
        static const(char)[] leftoverChars = "";

        if ( socketSet.isSet(_socket) )
        {
            char[BUFFER_SIZE] buffer;
            auto dataLength = _socket.receive(buffer[]);

            if (dataLength == Socket.ERROR)
            {
                throw new SocketReadException("receive returned Socket.ERROR", dataLength);
            }
            else if (dataLength == 0)
            {
                throw new SocketReadException("server closed connection", dataLength);
            }
            else
            {
                write(buffer[0 .. dataLength]);
                return handleChars!(ServerMessage, parseServerMessage)(leftoverChars, buffer[0 .. dataLength].idup);
            }
        }
        else if (leftoverChars.length > 0)
        {
            return handleChars!(ServerMessage, parseServerMessage)(leftoverChars, "");
        }
        else
        {
            return (Nullable!ServerMessage).init;
        }
    }

    Socket socket()
    {
        return _socket;
    }
}

final class SocketReadException : Exception
{
    private immutable ptrdiff_t result;

    this(string message, ptrdiff_t result, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, file, line);
        this.result = result;
    }

    ptrdiff_t getResult()
    {
        return result;
    }
}

final class ProtocolException : Exception
{
    this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, file, line);
    }
}

private Nullable!T handleChars(T, alias parseFunc)(ref const(char)[] leftoverChars, string fromSocket)
{
    auto fromSocketIndex = fromSocket.indexOf('\n');

    if (leftoverChars.length == 0 && fromSocketIndex != -1)
    {
        leftoverChars = fromSocket[fromSocketIndex + 1 .. $];
        return parseFunc(fromSocket[0 .. fromSocketIndex]);
    }

    auto index = leftoverChars.indexOf('\n');

    if (index == -1)
    {
        if (fromSocketIndex == -1) {
            leftoverChars ~= fromSocket;
            return (Nullable!T).init;
        }
        else {
            auto chars = leftoverChars;
            leftoverChars = fromSocket[fromSocketIndex + 1 .. $];
            return parseFunc(chars ~ fromSocket[0 .. fromSocketIndex]);
        }
    }
    else
    {
        auto line = leftoverChars[0 .. index];
        leftoverChars = leftoverChars[index + 1 .. $] ~ fromSocket;
        return parseFunc(line);
    }
}

private Nullable!ClientMessage parseClientMessage(in char[] line)
{
    if (line.strip().length == 0) {
        return (Nullable!ClientMessage).init;
    }

    auto words = line.split();
    const(char)[][] args;

    if (words.length > 1) {
        args = words[1 .. $];
    }

    switch (words[0])
    {
    case ClientMessageType.JOIN:
        return ClientMessage.parse!(string)(ClientMessageType.JOIN, args).nullable;
    case ClientMessageType.DRAW:
        return new ClientMessage(ClientMessageType.DRAW).nullable;
    case ClientMessageType.PLACE:
        return ClientMessage.parse!(int, int)(ClientMessageType.PLACE, args).nullable;
    case ClientMessageType.REJECT:
        return new ClientMessage(ClientMessageType.REJECT).nullable;
    case ClientMessageType.SWAP:
        return ClientMessage.parse!(int, int)(ClientMessageType.SWAP, args).nullable;
    case ClientMessageType.FLIP:
        return ClientMessage.parse!(int, int)(ClientMessageType.FLIP, args).nullable;
    case ClientMessageType.READY:
        return new ClientMessage(ClientMessageType.READY).nullable;
    case ClientMessageType.BYE:
        return new ClientMessage(ClientMessageType.BYE).nullable;
    default:
        throw new ProtocolException(("unsupported client message: " ~ line).idup);
    }
}

@system unittest
{
    alias handleCh = handleChars!(ClientMessage, parseClientMessage);

    const(char)[] leftoverChars = "";

    assert( handleCh(leftoverChars, "reject\n**").get.type == ClientMessageType.REJECT );
    assert(leftoverChars == "**");

    leftoverChars = "swap 1 3\n  ";
    auto message = handleCh(leftoverChars, "draw\n").get;
    assert(message.type == ClientMessageType.SWAP);
    assert(message.row == 1);
    assert(message.col == 3);
    assert(leftoverChars == "  draw\n");
    assert( handleCh(leftoverChars, "").get.type == ClientMessageType.DRAW );
    assert(leftoverChars == "");

    leftoverChars = "fli";
    assert( handleCh(leftoverChars, "p 1 1\n").get.type == ClientMessageType.FLIP );
    assert(leftoverChars == "");

    assert( handleCh(leftoverChars, "place 0 ") == (Nullable!ClientMessage).init );
    assert(leftoverChars == "place 0 ");
    assert( handleCh(leftoverChars, "0") == (Nullable!ClientMessage).init );
    assert(leftoverChars == "place 0 0");
    assert( handleCh(leftoverChars, "\n").get.type == ClientMessageType.PLACE );
    assert(leftoverChars == "");

    assert( handleCh(leftoverChars, "ready\nplace 0 0\ndraw\n").get.type == ClientMessageType.READY );
    assert( handleCh(leftoverChars, "").get.type == ClientMessageType.PLACE );
    assert( handleCh(leftoverChars, "").get.type == ClientMessageType.DRAW );
    assert( handleCh(leftoverChars, "") == (Nullable!ClientMessage).init  );
}

final class ClientMessage
{
    immutable
    {
        ClientMessageType type;
        string name;
        int row;
        int col;
    }
private:

    this(ClientMessageType type) pure nothrow
    {
        this.type = type;
        name = "";
        row = -1;
        col = -1;
    }

    this(ClientMessageType type, string name) pure nothrow
    {
        this.type = type;
        this.name = name;
        row = -1;
        col = -1;
    }

    this(ClientMessageType type, int row, int col) pure nothrow
    {
        this.type = type;
        this.row = row;
        this.col = col;
        name = "";
    }

    static ClientMessage parse(Seq...)(ClientMessageType msgType, const(char)[][] args)
    {
        return parseArgs!(ClientMessage, ClientMessageType, Seq)(msgType, args);
    }
}

enum ClientMessageType : string
{
    JOIN = "join",
    DRAW = "draw",
    PLACE = "place",
    REJECT = "reject",
    SWAP = "swap",
    FLIP = "flip",
    READY = "ready",
    BYE = "bye"
}

private Nullable!ServerMessage parseServerMessage(in char[] line)
{
    if (line.strip().length == 0) {
        return (Nullable!ServerMessage).init;
    }

    auto words = line.split();
    const(char)[][] args;

    if (words.length > 1) {
        args = words[1 .. $];
    }

    switch (words[0])
    {
    case ServerMessageType.DEAL:
        return ServerMessage.withPlayerNumber(ServerMessageType.DEAL, args[0]).nullable;
    case ServerMessageType.DISCARD_CARD:
        return ServerMessage.withCard(ServerMessageType.DISCARD_CARD, args[0]).nullable;
    case ServerMessageType.CHANGE_TURN:
        return ServerMessage.withPlayerNumber(ServerMessageType.CHANGE_TURN, args[0]).nullable;
    case ServerMessageType.DRAWPILE:
        return ServerMessage.withPlayerNumber(ServerMessageType.DRAWPILE, args[0]).nullable;
    case ServerMessageType.DRAWPILE_PLACE:
        return ServerMessage.parse!(int, int, int, int, int)(ServerMessageType.DRAWPILE_PLACE, args).nullable;
    case ServerMessageType.DRAWPILE_REJECT:
        return ServerMessage.drawpileReject(args[0].to!int, args[1].to!int).nullable;
    case ServerMessageType.REVEAL:
        return ServerMessage.parse!(int, int, int, int)(ServerMessageType.REVEAL, args).nullable;
    case ServerMessageType.DISCARD_SWAP:
        return ServerMessage.parse!(int, int, int, int, int)(ServerMessageType.DISCARD_SWAP, args).nullable;
    case ServerMessageType.COLUMN_REMOVAL:
        return ServerMessage.removeColumn(args[0].to!int, args[1].to!int).nullable;
    case ServerMessageType.LAST_TURN:
        return ServerMessage.withPlayerNumber(ServerMessageType.LAST_TURN, args[0]).nullable;
    case ServerMessageType.PLAYER_JOIN:
        return ServerMessage.parse!(int, string)(ServerMessageType.PLAYER_JOIN, args).nullable;
    case ServerMessageType.PLAYER_LEFT:
        return ServerMessage.withPlayerNumber(ServerMessageType.PLAYER_LEFT, args[0]).nullable;
    case ServerMessageType.WAITING:
        return ServerMessage.withPlayerNumber(ServerMessageType.WAITING, args[0]).nullable;
    case ServerMessageType.RECONNECTED:
        return ServerMessage.withPlayerNumber(ServerMessageType.RECONNECTED, args[0]).nullable;
    case ServerMessageType.CURRENT_SCORES:
        throw new Error("not implemented");
    case ServerMessageType.WINNER:
        return ServerMessage.withPlayerNumber(ServerMessageType.WINNER, args[0]).nullable;
    case ServerMessageType.YOUR_TURN:
        return new ServerMessage(ServerMessageType.YOUR_TURN).nullable;
    case ServerMessageType.CHOOSE_FLIP:
        return new ServerMessage(ServerMessageType.CHOOSE_FLIP).nullable;
    case ServerMessageType.YOU_ARE:
        return ServerMessage.withPlayerNumber(ServerMessageType.YOU_ARE, args[0]).nullable;
    case ServerMessageType.CARD:
        return ServerMessage.withCard(ServerMessageType.CARD, args[0]).nullable;
    case ServerMessageType.GRID_CARDS:
        return ServerMessage.gridCards(args).nullable;
    case ServerMessageType.IN_PROGRESS:
        return new ServerMessage(ServerMessageType.IN_PROGRESS).nullable;
    case ServerMessageType.FULL:
        return new ServerMessage(ServerMessageType.FULL).nullable;
    case ServerMessageType.NAME_TAKEN:
        return new ServerMessage(ServerMessageType.NAME_TAKEN).nullable;
    case ServerMessageType.KICKED:
        return new ServerMessage(ServerMessageType.KICKED).nullable;
    case ServerMessageType.NEW_GAME:
        return new ServerMessage(ServerMessageType.NEW_GAME).nullable;
    default:
        throw new ProtocolException(("unrecognized server message: " ~ line).idup);
    }
}

final class ServerMessage
{
    immutable
    {
        ServerMessageType type;
        int playerNumber;
        int row;
        int col;
        CardRank card1;
        CardRank card2;
        string name;
    }
    Card[][] cards;

private:

    this(ServerMessageType type) pure nothrow
    {
        this.type = type;
        playerNumber = -1;
        row = -1;
        col = -1;
        card1 = CardRank.UNKNOWN;
        card2 = CardRank.UNKNOWN;
        name = "";
        cards = null;
    }

    this(ServerMessageType type, int player, int row, int col, int card1) pure
    {
        this.type = type;
        this.playerNumber = player;
        this.row = row;
        this.col = col;
        this.card1 = intToCard(card1);
        name = "";
        card2 = CardRank.UNKNOWN;
        cards = null;
    }

    this(ServerMessageType type, int player, int row, int col, int card1, int card2) pure
    {
        this.type = type;
        this.playerNumber = player;
        this.row = row;
        this.col = col;
        this.card1 = intToCard(card1);
        this.card2 = intToCard(card2);
        name = "";
        cards = null;
    }

    this(ServerMessageType type, int playerNumber, string name) pure
    {
        enforce!Error(name !is null, "name cannot be null");

        this.type = type;
        this.playerNumber = playerNumber;
        this.name = name;
        row = -1;
        col = -1;
        card1 = CardRank.UNKNOWN;
        card2 = CardRank.UNKNOWN;
        cards = null;
    }

    this(ServerMessageType type, int playerNumber, Card[][] cards)
    {
        this.type = type;
        this.playerNumber = playerNumber;
        this.cards = new Card[][3];
        this.cards[0] = cards[0].dup;
        this.cards[1] = cards[1].dup;
        this.cards[2] = cards[2].dup;
        row = -1;
        col = -1;
        card1 = CardRank.UNKNOWN;
        card2 = CardRank.UNKNOWN;
        name = "";
    }

    this(ServerMessageType type, int playerNumber, CardRank card, int col) pure
    {
        this.type = type;
        this.playerNumber = playerNumber;
        this.card1 = card;
        this.col = col;
        card2 = CardRank.UNKNOWN;
        row = -1;
        name = "";
        cards = null;
    }

    static ServerMessage withPlayerNumber(ServerMessageType type, in char[] playerNumber) pure
    {
        return new ServerMessage(type, playerNumber.to!int, CardRank.UNKNOWN, -1);
    }

    static ServerMessage withCard(ServerMessageType type, in char[] card) pure
    {
        return new ServerMessage(type, -1, card.to!(int).intToCard, -1);
    }

    static ServerMessage drawpileReject(int player, int card) pure
    {
        return new ServerMessage(ServerMessageType.DRAWPILE_REJECT, player, intToCard(card), -1);
    }

    static ServerMessage removeColumn(int player, int col) pure
    {
        enforce!ProtocolException(col >= 0 && col <= 3, "illegal column number: " ~ col.to!string);

        return new ServerMessage(ServerMessageType.COLUMN_REMOVAL, player, CardRank.UNKNOWN, col);
    }

    static ServerMessage gridCards(const(char)[][] args)
    {
        enforce!ProtocolException(args.length == 13,
                "expected 12 cards, received " ~ (args.length - 1).to!string ~ ": " ~ args.join(" ").idup);

        Card[][] cards = new Card[][3];
        cards[0] = new Card[4];
        cards[1] = new Card[4];
        cards[2] = new Card[4];

        // first number is player number, cards are indexes 1-12
        foreach (size_t i; 0 .. 12)
        {
            Card c;
            size_t k = i + 1;

            if (args[k] == "_") {
                c = null;
            }
            else if (args[k] == "?") {
                c = new Card(CardRank.UNKNOWN);
            }
            else {
                c = new Card(args[k].to!(int).intToCard);
                c.revealed = true;
            }
            cards[i / 4][i % 4] = c;
        }
        return new ServerMessage(ServerMessageType.GRID_CARDS, args[0].to!int, cards);
    }

    static ServerMessage parse(Seq...)(ServerMessageType msgType, const(char)[][] args)
    {
        return parseArgs!(ServerMessage, ServerMessageType, Seq)(msgType, args);
    }
}

enum ServerMessageType : string
{
    DEAL = "deal",
    DISCARD_CARD = "discard_card",
    CHANGE_TURN = "turn",
    DRAWPILE = "drawpile",
    DRAWPILE_PLACE = "drawpile_place",
    DRAWPILE_REJECT = "drawpile_reject",
    REVEAL = "reveal",
    DISCARD_SWAP = "discard_swap",
    COLUMN_REMOVAL = "remove_col",
    LAST_TURN = "last_turn",
    PLAYER_JOIN = "player",
    PLAYER_LEFT = "left",
    WAITING = "waiting",
    RECONNECTED = "reconnected",
    CURRENT_SCORES = "score",
    WINNER = "winner",

    YOUR_TURN = "your_turn",
    CHOOSE_FLIP = "choose_flip",
    YOU_ARE = "you_are",
    CARD = "card",
    GRID_CARDS = "cards",
    IN_PROGRESS = "in_progress",
    FULL = "full",
    NAME_TAKEN = "name_taken",
    KICKED = "kicked",
    NEW_GAME = "new_game"
}

private auto parseArgs(M, T, Seq...)(T msgType, const(char)[][] args)
{
    if (args.length != Seq.length) {
        throw new ProtocolException((msgType ~ " - wrong number of parameters: " ~ args.join(" ")).idup);
    }

    Tuple!Seq result;

    foreach (i, Type; Seq)
    {
        result[i] = args[i].to!Type;
    }
    return new M(msgType, result[]);
}

private pure CardRank intToCard(int rank)
{
    if (rank >= -2 && rank <= 12)
    {
        return cast(CardRank) rank;
    }
    else
    {
        throw new ProtocolException("invalid rank number: " ~ rank.to!string);
    }
}
