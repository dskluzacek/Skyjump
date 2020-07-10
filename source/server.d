module server;
@safe:

import std.stdio;
import std.algorithm : each, remove, all, count;
import std.string : strip;
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

    for (;;)
    {
        pollSockets();

        receiveTimeout(0.usecs, (string command) {
            command = command.strip();

            if (command == "start")
            {
                if (model.numberOfPlayers() < 2)
                {
                    writeMsg("Can't start the game - not enough players");
                }
                else if (model.getState != GameState.NOT_STARTED && model.getState != GameState.END_GAME)
                {
                    writeMsg("Game already in progress");
                }
                else
                {
                    foreach (client; clients) {
                        client.readyReceived = false;
                    }
                    model.deal();
                    write("$ ");
                    stdout.flush();
                }
            }
            else if (command == "next")
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
                    foreach (client; clients) {
                        client.readyReceived = false;
                    }
                    model.nextHand();
                    model.deal();
                    write("$ ");
                    stdout.flush();
                }
            }
            else if (command.length > 0)
            {
                writeMsg("Command not recognized");
            }
            else
            {
                write("$ ");
                stdout.flush();
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
        playerReconnect(client, disconnectedPlayers[0], name);
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
        else
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
        model.getPlayerOut().ifPresent!( a => client.lastTurn(a) );

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
    writeMsg("\n", state);

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
                client.changeTurn( model.getCurrentPlayerTurn);
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
    writeMsg("\nclientReady");

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
        model.removeObserver(client);
        model.playerLeft(client.player);
        closeConnection(client);
    }
}

void pollSockets() @trusted
{
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

    for (size_t i = 0; i < clients.length; i++)
    {
        if (clients[i].isMarkedForRemoval)
        {
            clients = clients.remove(i);
            i--;
        }
    }
}

// terminate the connection of a misbehaving client but keep player in the game
void closeAndWaitForReconnect(ConnectedClient client)
{
    if (model.getState != GameState.NOT_STARTED && model.getState != GameState.END_GAME)
    {
        ServerPlayer p = client.player;
        disconnectedPlayers ~= p;
        model.removeObserver(client);
        model.waitForReconnect(p);
        p.client = null;
        closeConnection(client);
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
