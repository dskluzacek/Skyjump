module server;
@safe:

import std.stdio;
import std.algorithm : each, remove, all, count;
import std.conv;
import std.uni : toLower;
import std.array : split;
import std.concurrency;
import std.socket;
import std.typecons;
import core.time;
import core.thread;

import util;
import gamemodel;
import player;
import playergrid;
import card;
import net;

enum ushort PORT = 7684;
enum BACKLOG = 5;
enum MAX_PLAYERS = 5;

private
{
    Socket listenerSocket;
    SocketSet socketSet;
    Tid consoleThread;
    ConnectedClient[] clients;
    ServerPlayer[] disconnectedPlayers;
    ServerGameModel model;
}

static this()
{
    socketSet = new SocketSet();
}

void main() @system
{
    listenerSocket = new TcpSocket();
    listenerSocket.blocking = false;
    listenerSocket.bind(new InternetAddress(PORT));
    listenerSocket.listen(BACKLOG);

    write("\n$ ");
    consoleThread = spawn(&consoleReader, thisTid);
    bool quit;

    while (! quit)
    {
        pollSockets();

        receiveTimeout(0.usecs, (string command) {
            auto args = command.split();

            if (args.length < 1)
            {
                write("$ ");
                stdout.flush();
            }
            else if (args[0] == "start")
            {
                startGame();
            }
            else if (args[0] == "next")
            {
                startNextHand();
            }
            else if (args[0] == "list")
            {
                listPlayers();
            }
            else if (args[0] == "drop")
            {
                if (args.length >= 2) {
                    try {
                        dropPlayer(args[1].to!int);
                    }
                    catch (ConvException e) {
                        writeMsg("Invalid number");
                    }
                }
                else {
                    writeMsg("Need player number");
                }
            }
            else if (args[0] == "kick")
            {
                if (args.length >= 2)
                {
                    try {
                        kickPlayer(args[1].to!int);
                    }
                    catch (ConvException e) {
                        writeMsg("Invalid number");
                    }
                }
                else {
                    writeMsg("Need player number");
                }
            }
            else if (args[0] == "set")
            {
                if (args.length == 5)
                {
                    try {
                        setCard(args[1 .. $]);
                    }
                    catch (Exception e) {
                        writeMsg("Invalid argument");
                    }
                }
                else {
                    writeMsg("Wrong number of arguments");
                }
            }
            else
            {
                writeMsg("Command not recognized");
            }
        });
    }
}

void consoleReader(Tid ownerTid) @trusted
{
    char[] buffer;
    size_t readLength;

    do
    {
        readLength = readln(buffer);
        ownerTid.send(buffer.idup);
    }
    while (readLength > 0);
}

void writeMsg(T...)(T args) @trusted
{
    writeln(args);
    write("$ ");
    stdout.flush();
}

void setCard(string[] args)
{
    ubyte index = args[0].to!ubyte;
    ubyte row = args[1].to!ubyte;
    ubyte col = args[2].to!ubyte;
    auto rank = args[3].to!byte;

    if (! model.hasPlayer(index) || row > 2 || col > 3 || rank < -2 || rank > 12) {
        throw new Exception("invalid argument");
    }

    model[index][row, col] = new Card(rank.to!CardRank);
    writeMsg();
}

void startGame()
{
    if (model.numberOfPlayers() < 2)
    {
        writeMsg("Can't start the game - not enough players");
    }
    else if (disconnectedPlayers.length > 0)
    {
        writeMsg("Can't start the game - there are disconnected players");
    }
    else if (model.getState != GameState.NOT_STARTED && model.getState != GameState.END_GAME)
    {
        writeMsg("Game already in progress");
    }
    else
    {
        if (model.getState() == GameState.END_GAME) {
            model.newGame();
        }
        deal();
    }
}

void startNextHand()
{
    if (model.getState != GameState.BETWEEN_HANDS)
    {
        writeMsg("Can't start a new hand - not between hands");
    }
    else if (disconnectedPlayers.length > 0)
    {
        writeMsg("Can't start a new hand - not all players connected");
    }
    else
    {
        model.nextHand();
        deal();
    }
}

void deal() @trusted
{
    foreach (client; clients) {
        client.readyReceived = false;
    }
    model.deal();
    write("$ ");
    stdout.flush();
}

void listPlayers()
{
    writeln("Connected players:");

    foreach (client; clients)
    {
        Player p = client.player;
        writeln(model.playerNumberOf(p), " - ", p.getName);
    }

    writeln("\nDisconnected players:");

    foreach (p; disconnectedPlayers)
    {
        writeln(model.playerNumberOf(p), " - ", p.getName);
    }
    writeMsg();
}

void dropPlayer(int number)
{
    if (model.numberOfPlayers < 3) {
        writeMsg("Can't drop a player - not enough players would remain");
        return;
    }

    foreach (client; clients)
    {
        if (model.playerNumberOf(client.player) == number)
        {
            closeAndWaitForReconnect(client);
            return;
        }
    }
    writeMsg("No connected players with that number");
}

void kickPlayer(int number)
{
    if (model.numberOfPlayers < 3) {
        writeMsg("Can't kick a player - not enough players would remain");
        return;
    }

    foreach (client; clients)
    {
        if (model.playerNumberOf(client.player) == number)
        {
            client.send(ServerMessageType.KICKED);
            playerLeave(client);
            return;
        }
    }

    foreach (player; disconnectedPlayers)
    {
        if (model.playerNumberOf(player) == number)
        {
            model.playerLeft(player);
            disconnectedPlayers = disconnectedPlayers.remove!( a => a is player );

            if (disconnectedPlayers.length == 0) {
                model.allPlayersReconnected();
            }
            writeMsg("Removed disconnected player");
            return;
        }
    }
    writeMsg("No players with that number");
}

void handleMessage(ClientMessage message, ConnectedClient client)
{
    final switch (message.type)
    {
    case ClientMessageType.JOIN:
        playerJoin(client, message.name);
        break;
    case ClientMessageType.DRAW:
        playerDraw(client);
        break;
    case ClientMessageType.PLACE:
        playerPlaceDrawnCard(client, message.row, message.col);
        break;
    case ClientMessageType.REJECT:
        playerRejectDrawnCard(client);
        break;
    case ClientMessageType.SWAP:
        playerTakeDiscardCard(client, message.row, message.col);
        break;
    case ClientMessageType.FLIP:
        playerFlipCard(client, message.row, message.col);
        break;
    case ClientMessageType.READY:
        clientReady(client);
        break;
    case ClientMessageType.BYE:
        playerLeave(client);
        break;
    }
}

void playerJoin(ConnectedClient client, string name)
{
    if (disconnectedPlayers.length == 1)
    {
        if ( ! checkIfNameTaken(name, client) ) {
            playerReconnect(client, disconnectedPlayers[0], name);
        }
        return;
    }
    else if (disconnectedPlayers.length > 1)
    {
        foreach (player; disconnectedPlayers)
        {
            if (player.getName() == name) {
                playerReconnect(client, player, name);
                return;
            }
        }

        client.send(ServerMessageType.IN_PROGRESS);
        closeConnection(client);
        return;
    }

    if (client.waitingForJoin)
    {
        if (model.getState != GameState.NOT_STARTED)
        {
            client.send(ServerMessageType.IN_PROGRESS);
            closeConnection(client);
        }
        else if (model.numberOfPlayers >= MAX_PLAYERS)
        {
            client.send(ServerMessageType.FULL);
            closeConnection(client);
        }
        else if ( ! checkIfNameTaken(name, client) )
        {
            playerAdd(client, name);
        }
    }
    else
    {
        // error (join allowed only once)
        closeAndWaitForReconnect(client);
    }
}

bool checkIfNameTaken(string name, ConnectedClient joining)
{
    name = name.toLower;

    foreach (client; clients)
    {
        if (! client.waitingForJoin && client.player.getName.toLower == name)
        {
            joining.send(ServerMessageType.NAME_TAKEN);
            joining.closeConnection;
            return true;
        }
    }

    return false;
}

void playerAdd(ConnectedClient client, string name)
{
    auto p = new ServerPlayer(name, client);
    auto playerNumber = model.addPlayer(p, client);
    client.player = p;
    client.waitingForJoin = false;
    client.send(ServerMessageType.YOU_ARE, playerNumber);

    foreach (key; model.playerKeys())
    {
        if (key != playerNumber) {
            client.playerJoined(key, model[key].getName);
        }
    }
}

void playerReconnect(ConnectedClient client, ServerPlayer player, string name)
in {
    assert(disconnectedPlayers.length > 0);
}
body
{
    int playerNumber = model.playerNumberOf(player);

    if (playerNumber != -1)  // player was found in model
    {
        player.setName(name);
        player.client = client;
        client.player = player;
        client.waitingForJoin = false;

        client.send(ServerMessageType.YOU_ARE, playerNumber);
        if (player.hasGrid) {
            client.updateCards(playerNumber, player.getGrid);
        }

        foreach (key; model.playerKeys())
        {
            if (key != playerNumber)
            {
                client.playerJoined(key, model[key].getName);
                if (model[key].hasGrid) {
                    client.updateCards(key, model[key].getGrid);
                }
            }
        }
        client.currentScores(model);
        model.getDiscardTopCard().ifPresent!( c => client.send(ServerMessageType.DISCARD_CARD, cast(int) c.rank) );
        model.getPlayerOut().ifPresent!((a) {
            if (model.getState != GameState.BETWEEN_HANDS)
                client.lastTurn(a);
        });

        disconnectedPlayers = disconnectedPlayers.remove!( a => a is player );

        model.playerReconnected(player);
        model.addObserver(client);
        sendReconnectStateInfo(client);

        disconnectedPlayers.each!( a => client.waiting(model.playerNumberOf(a)) );
    }
    else
    {
        writeMsg("\nERROR: upon reconnect, player not found in GameModel");
        disconnectedPlayers = disconnectedPlayers.remove!( a => a is player );
        closeConnection(client);
    }

    if (disconnectedPlayers.length == 0) {
        model.allPlayersReconnected();
    }
}

void sendReconnectStateInfo(ConnectedClient client)
{
    GameState state = model.getState();

    final switch (state)
    {
    case GameState.NOT_STARTED:
        throw new Error("Illegal state (GameState.NOT_STARTED)");
    case GameState.DEALING:
        // act as if client finished deal animation and sent ready
        clientReady(client);
        break;
    case GameState.FLIP_CHOICE:
        client.chooseFlip();
        break;
    case GameState.PLAYER_TURN:
        if (model.playerWhoseTurnItIs is client.player)
        {
            if (disconnectedPlayers.length > 0) {          // don't send if this was the last player to reconnect
                client.send(ServerMessageType.YOUR_TURN);  // as the model will notify observers
            }
            model.getDrawnCard().ifPresent!((c) {
                client.send(ServerMessageType.CARD, cast(int) c.rank);
            });
        }
        else
        {
            if (disconnectedPlayers.length > 0) {
                client.changeTurn(model.getCurrentPlayerTurn);
            }
            model.getDrawnCard().ifPresent!((c) {
                client.drawpile(model.getCurrentPlayerTurn);
            });
        }
        break;
    case GameState.BETWEEN_HANDS:
        // do nothing
        break;
    case GameState.END_GAME:
        throw new Error("Illegal state/not implemented (GameState.END_GAME)");
    }
}

void clientReady(ConnectedClient client)
{
    if (model.getState != GameState.DEALING) {
        writeMsg("\nERROR: clientReady during invalid state: ", model.getState);
        return;
    }

    client.readyReceived = true;

    if (clients.all!(c => c.readyReceived) && disconnectedPlayers.length == 0)
    {
        model.beginFlipChoices();
    }
}

void playerDraw(ConnectedClient client)
{
    if (model.getState == GameState.PLAYER_TURN
            && model.playerWhoseTurnItIs is client.player
            && ! model.hasDrawnCard
            && disconnectedPlayers.length == 0)
    {
        Card c = model.drawCard();
        client.send(ServerMessageType.CARD, cast(int) c.rank);
    }
    else
    {
        // error
        closeAndWaitForReconnect(client);
    }
}

void playerPlaceDrawnCard(ConnectedClient client, int row, int col)
{
    if (row < 0 || row > 2 || col < 0 || col > 3) {
        closeAndWaitForReconnect(client);
        return;
    }

    if (model.getState == GameState.PLAYER_TURN
            && model.playerWhoseTurnItIs is client.player
            && model.hasDrawnCard
            && client.player[row, col].isNotNull
            && disconnectedPlayers.length == 0)
    {
        model.exchangeDrawnCard(row, col);   // model will notify all clients
    }
    else
    {
        // error
        closeAndWaitForReconnect(client);
    }
}

void playerRejectDrawnCard(ConnectedClient client)
{
    if (model.getState == GameState.PLAYER_TURN
            && model.playerWhoseTurnItIs is client.player
            && model.hasDrawnCard
            && disconnectedPlayers.length == 0)
    {
        model.discardDrawnCard();
    }
    else
    {
        // error
        closeAndWaitForReconnect(client);
    }
}

void playerTakeDiscardCard(ConnectedClient client, int row, int col)
{
    if (row < 0 || row > 2 || col < 0 || col > 3 || disconnectedPlayers.length > 0) {
        closeAndWaitForReconnect(client);
        return;
    }

    if (model.getState == GameState.PLAYER_TURN
            && model.playerWhoseTurnItIs is client.player
            && ! model.hasDrawnCard
            && client.player[row, col].isNotNull
            && disconnectedPlayers.length == 0)
    {
        model.takeDiscardCard(row, col);
    }
    else
    {
        closeAndWaitForReconnect(client);
    }
}

void playerFlipCard(ConnectedClient client, int row, int col)
{
    if (row < 0 || row > 2 || col < 0 || col > 3 || client.player[row, col].isNull || disconnectedPlayers.length > 0)
    {
        closeAndWaitForReconnect(client);
        return;
    }

    if (model.getState == GameState.PLAYER_TURN && ! model.hasDrawnCard
         && model.playerWhoseTurnItIs is client.player
         && client.player[row, col].get.revealed == false)
    {
        model.flipCard(row, col);
    }
    else if (model.getState == GameState.FLIP_CHOICE
              && client.player.getGrid.getCardsAsRange.count!(a => a.revealed) < 2
              && client.player[row, col].get.revealed == false)
    {
        model.flipCard(client.player, row, col);
    }
    else
    {
        closeAndWaitForReconnect(client);
    }
}

void playerLeave(ConnectedClient client)
{
    if (client.waitingForJoin)
    {
        closeConnection(client);
    }
    else
    {
        auto p = client.player;
        auto playerNumber = model.playerNumberOf(p).to!string;

        model.removeObserver(client);
        model.playerLeft(p);
        closeConnection(client);

        if (model.getState != GameState.NOT_STARTED && model.numberOfPlayers < 2)
        {
            write("\nEnding game - not enough players left");
            reset();
        }

        writeMsg('\n' ~ p.getName ~ " (" ~ playerNumber ~ ") left.");
    }
}

void reset()
{
    model.reset();
    disconnectedPlayers = [];

    foreach (c; clients) {
        closeConnection(c);
    }
}

void pollSockets() @trusted
{
    for (size_t i = 0; i < clients.length; i++)
    {
        if (clients[i].isMarkedForRemoval)
        {
            clients = clients.remove(i);
            i--;
        }
    }

    socketSet.reset();
    socketSet.add(listenerSocket);

    foreach (client; clients) {
        socketSet.add(client.socket);
    }

    auto result = Socket.select(socketSet, null, null, dur!"usecs"(100));

    if (result < 1) {
        return;
    }

    foreach (client; clients)
    {
        try {
            Nullable!ClientMessage msg = client.poll(socketSet);
            msg.ifPresent!( m => handleMessage(m, client) );
        }
        catch (Exception e) {
            if (client.isMarkedForRemoval) {
                writeMsg("\nclient marked for removal / ", e.msg);
                continue;
            }
            else if (client.waitingForJoin) {
                writeMsg("\nclosing connection before join / ", e.msg);
                closeConnection(client);
            }
            else {
                writeMsg("\nclosing connection / ", e.msg);
                closeAndWaitForReconnect(client);
            }
        }
    }

    if ( socketSet.isSet(listenerSocket) )   // connection request
    {
        Socket sock = null;

        try {
            sock = listenerSocket.accept();
            auto client = new ConnectedClient(sock);
            clients ~= client;
        }
        catch (SocketAcceptException e) {
            writeMsg("\nError accepting: ", e.msg);

            if (sock) {
                sock.close();
            }
        }
    }
}

// terminate the connection of a misbehaving client but keep player in the game
void closeAndWaitForReconnect(ConnectedClient client)
{
    ServerPlayer p = client.player;
    auto playerNumber = model.playerNumberOf(p).to!string;

    if (model.getState != GameState.NOT_STARTED && model.getState != GameState.END_GAME)
    {
        disconnectedPlayers ~= p;
        model.removeObserver(client);
        model.waitForReconnect(p);
        p.client = null;
        closeConnection(client);

        writeMsg("\nTerminated connection of " ~ p.getName ~ " (" ~ playerNumber ~ ')');
    }
    else
    {
        playerLeave(client);
    }
}

void closeConnection(ConnectedClient client) nothrow @nogc
{
    Socket s = client.socket();
    s.shutdown(SocketShutdown.BOTH);
    s.close();
    client.markForRemoval();
}
