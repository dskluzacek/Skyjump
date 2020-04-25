module skyjo;
@safe:

import std.stdio;
import std.algorithm;
import std.array;
import std.typecons;
import std.functional;
import std.datetime : Clock;
import std.string : toStringz;
import std.socket;
import std.conv;
import core.time;
import core.thread;

import derelict.sdl2.mixer;
import sdl2.sdl,
       sdl2.window,
       sdl2.renderer,
       sdl2.texture,
       sdl2.image,
       sdl2.mixer,
       sdl2.ttf;

import gamemodel;
import keyboard;
import background;
import animation;
import card;
import player;
import playergrid;
import net;
import util;
import label;

enum window_title = "Skyjo";
enum version_str  = "pre-alpha";

enum draw_pile_position = Point(692, 15);
enum discard_pile_position = Point(1056, 15);

enum total_audio_channels        = 8,
     num_reserved_audio_channels = 3;

auto unknown_card = new immutable Card(CardRank.UNKNOWN);

static this()
{
//	drawPile = new Card(CardRank.UNKNOWN);
	opponentGrids = new OpponentGrid[4];
	socketSet = new SocketSet();
}

private
{
	GameModel model;
	UIMode currentMode = UIMode.PRE_GAME;
	ubyte localPlayerNumber;
	LocalPlayer localPlayer;
	SocketSet socketSet;
	ConnectionToServer connection;
	OpponentGrid[] opponentGrids;
	Background gameBackground;
	Font font;
	Sound drawSound;
	Card discardPile;
	DealAnimation dealAnim;
	Point lastMousePosition;
	ubyte cardsRevealed;

	alias drawPile = unknown_card;
}

enum UIMode
{
	PRE_GAME,
	DEALING,
	NO_ACTION,
	FLIP_ACTION,
	OPPONENT_TURN,
	MY_TURN_ACTION,
	DRAWN_CARD_ACTION,
	WAITING
}

void main(string[] args) @system
{
	string name = "David";

	try {
		if (args.length >= 2) {
			name = args[1];
		}
		writeln;

		localPlayer = new LocalPlayer(name);
		run();
		return;
	}
	catch (Error err) {
		logFatalException(err, "Runtime error");
		debug writeln('\n', err);
	}
	catch (Throwable ex) {
		logFatalException(ex, "Uncaught exception");
		debug writeln('\n', ex);
	}

	if ( DerelictSDL2.isLoaded() )
	{
		showErrorDialog("An error occurred and Skyjo is closing.");
	}
}

void shutdown()
{
	SDL2.quit();
}

bool initialize(out Window window, out Renderer renderer) @system
{
	/* -- Initialize SDL, utility libs, and mixer channels -- */
	try {
		SDL2.start( SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_EVENTS );
		initSDL_image();
		initSDL_mixer();
		initSDL_ttf();
		openAudio();
		Mix_AllocateChannels(total_audio_channels);
		Mix_ReserveChannels(num_reserved_audio_channels);

		// enable OpenGL multisampling
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 1);
		SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 16);
	}
	catch (DerelictException e) {
		logFatalException(e, "Failed to load the SDL2 shared library");
		return false;
	}
	catch (SDL2Exception e) {
		showErrorDialog(e, "SDL could not be initialized", Yes.logToFile);
		return false;
	}

	/* -- Create window and renderer -- */
	try {
		window = Window( window_title,
		SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
		1600, 900,
		SDL_WINDOW_HIDDEN
//		| SDL_WINDOW_MAXIMIZED
		| SDL_WINDOW_RESIZABLE );

		renderer = window.createRenderer( SDL_RENDERER_ACCELERATED
		                                  | SDL_RENDERER_PRESENTVSYNC );

		SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "best");

		return true;
	}
	catch (SDL2Exception e) {
		showErrorDialog(e, "Failed to create the window or renderer", Yes.logToFile);
		return false;
	}
}

void run() @system
{
	Window window;
	Renderer renderer;

	scope(exit) shutdown();

	if ( ! initialize(window, renderer) ) {
		return;
	}
	bool quit = false;

	auto controller = KeyboardController();
	controller.setQuitHandler( { quit = true; } );

	load(renderer);
	window.visible = true;
	masterLoop(window, renderer, quit, controller);
}

void load(ref Renderer renderer)
{
	localPlayer.setGrid( new ClickablePlayerGrid(Point(586, 320)) );

	font = openFont("assets/DejaVuSerifCondensed-Bold.ttf", 72);

	opponentGrids[0] = new OpponentGrid(Point(40, 580), NamePlacement.ABOVE, font, renderer);
	opponentGrids[1] = new OpponentGrid(Point(40, 40), NamePlacement.BELOW, font, renderer);
	opponentGrids[2] = new OpponentGrid(Point(1464, 40), NamePlacement.BELOW, font, renderer);
	opponentGrids[3] = new OpponentGrid(Point(1464, 580), NamePlacement.ABOVE, font, renderer);

	gameBackground = new Background( renderer.loadTexture("assets/wood.png") );

	Card.setTexture( CardRank.NEGATIVE_TWO, renderer.loadTexture("assets/-2.png") );
	Card.setTexture( CardRank.NEGATIVE_ONE, renderer.loadTexture("assets/-1.png") );
	Card.setTexture( CardRank.ZERO, renderer.loadTexture("assets/0.png") );
	Card.setTexture( CardRank.ONE, renderer.loadTexture("assets/1.png") );
	Card.setTexture( CardRank.TWO, renderer.loadTexture("assets/2.png") );
	Card.setTexture( CardRank.THREE, renderer.loadTexture("assets/3.png") );
	Card.setTexture( CardRank.FOUR, renderer.loadTexture("assets/4.png") );
	Card.setTexture( CardRank.FIVE, renderer.loadTexture("assets/5.png") );
	Card.setTexture( CardRank.SIX, renderer.loadTexture("assets/6.png") );
	Card.setTexture( CardRank.SEVEN, renderer.loadTexture("assets/7.png") );
	Card.setTexture( CardRank.EIGHT, renderer.loadTexture("assets/8.png") );
	Card.setTexture( CardRank.NINE, renderer.loadTexture("assets/9.png") );
	Card.setTexture( CardRank.TEN, renderer.loadTexture("assets/10.png") );
	Card.setTexture( CardRank.ELEVEN, renderer.loadTexture("assets/11.png") );
	Card.setTexture( CardRank.TWELVE, renderer.loadTexture("assets/12.png") );
	Card.setTexture( CardRank.UNKNOWN, renderer.loadTexture("assets/back.png") );

	drawSound = loadWAV("assets/playcard.wav");
}

void masterLoop( ref Window window,
                 ref Renderer renderer,
                 ref bool quit,
                 ref KeyboardController controller )
{
//	MoveAnimation anim = new MoveAnimation(card, card_large_width, card_large_height, Point(0, 0), Point(150, 600), 750.msecs);



	Socket socket = new TcpSocket();
	socket.connect(new InternetAddress("localhost", 7685));
	connection = new ConnectionToServer(socket);
	connection.send(ClientMessageType.JOIN, localPlayer.getName);
	socket.blocking = false;

	//model.setPlayer(localPlayer, 0);
	//playerJoined(1, "Joe");
	//playerJoined(2, "Dan");
	//playerJoined(3, "Blake");
	//playerJoined(4, "Greg");

	mainLoop(window, renderer, quit, controller);
}

void mainLoop( ref Window window,
               ref Renderer renderer,
               ref bool quit,
               ref KeyboardController controller )
{
	auto grid = localPlayer.getGrid();

	addObserver!"mouseDown"( (event) {
		grid.mouseButtonDown(Point(event.x, event.y));
	});

	addObserver!"mouseUp"( (event) {
		grid.mouseButtonUp(Point(event.x, event.y));
	});

	addObserver!"mouseMotion"( (event) {
		grid.mouseMoved(Point(event.x, event.y));
	});

	grid.setClickHandler((int r, int c) {}.asDelegate);

	MonoTime currentTime;
	MonoTime lastTime = MonoTime.currTime();

	while (! quit)
	{
		currentTime = MonoTime.currTime();
		auto elapsed = currentTime - lastTime;

		if ( elapsed < dur!"usecs"(16_600) )
		{
			sleepFor(dur!"usecs"(16_600) - elapsed);
		}
		currentTime = MonoTime.currTime();
		elapsed = currentTime - lastTime;
		lastTime = currentTime;

		pollServer(connection);
		pollInputEvents(quit, controller);

		if (currentMode == UIMode.DEALING)
		{
			if ( dealAnim.isFinished() ) {  // isFinished has side effects!
				connection.send(ClientMessageType.READY);
				currentMode = UIMode.NO_ACTION;
			}
		}

		render(window, renderer, grid);
	}
}

void render(ref Window window, ref Renderer renderer, ClickablePlayerGrid grid)
{
	renderer.clear();
	renderer.setLogicalSize(0, 0);
	gameBackground.render(renderer, window);
	renderer.setLogicalSize(1920, 1080);

	bool windowHasFocus = window.testFlag(SDL_WINDOW_INPUT_FOCUS);

	if (windowHasFocus && currentMode == UIMode.FLIP_ACTION) {
		grid.setHighlightingMode(ClickablePlayerGrid.HighlightingMode.SELECTION);
	}
	else {
		grid.setHighlightingMode(ClickablePlayerGrid.HighlightingMode.OFF);
	}

	grid.render(renderer);
	opponentGrids.each!( opp => opp.render(renderer) );

	drawPile.draw(renderer, draw_pile_position, card_large_width, card_large_height);

	if (discardPile !is null) {
		discardPile.draw(renderer, discard_pile_position, card_large_width, card_large_height);
	}

	if (currentMode == UIMode.DEALING) {
		dealAnim.render(renderer);
	}

	renderer.present();
}

void sleepFor(Duration d) @trusted @nogc
{
	Thread.getThis().sleep(d);
}

void pollServer(ConnectionToServer connection)
{
	socketSet.reset();
	socketSet.add(connection.socket);
	int result = Socket.select(socketSet, null, null, dur!"usecs"(100));

	Nullable!ServerMessage message = connection.poll(socketSet);

	message.ifPresent!(handleMessage);
}

/**
 * Processes input events from the SDL event queue
 */
void pollInputEvents(ref bool quit, ref KeyboardController controller)
{
	@trusted auto poll(ref SDL_Event ev)
	{
		return SDL_PollEvent(&ev);
	}

	SDL_Event e;

	while ( poll(e) )
	{
		// If user closes the window:
		if (e.type == SDL_QUIT)
		{
			quit = true;
			break;
		}
		// If the event is a keyboard event:
		else if (e.type == SDL_KEYDOWN || e.type == SDL_KEYUP)
		{
			controller.handleEvent(e.key); // e.key is SDL_KeyboardEvent field in SDL_Event
		}
		else if (e.type == SDL_MOUSEMOTION)
		{
			lastMousePosition.x = e.motion.x;
			lastMousePosition.y = e.motion.y;

			notifyObservers!"mouseMotion"(e.motion);
		}
		else if (e.type == SDL_MOUSEBUTTONDOWN && e.button.button == SDL_BUTTON_LEFT)
		{
			notifyObservers!"mouseDown"(e.button);
		}
		else if (e.type == SDL_MOUSEBUTTONUP && e.button.button == SDL_BUTTON_LEFT)
		{
			notifyObservers!"mouseUp"(e.button);
		}
	}
}

mixin Observable!("mouseMotion", SDL_MouseMotionEvent);
mixin Observable!("mouseDown", SDL_MouseButtonEvent);
mixin Observable!("mouseUp", SDL_MouseButtonEvent);

void handleMessage(ServerMessage message)
{
	final switch (message.type)
	{
	case ServerMessageType.DEAL:
		currentMode = UIMode.DEALING;
		beginDealing(message.playerNumber);
		break;
	case ServerMessageType.DISCARD_CARD:
		Card c = new Card(message.card1);
		c.revealed = true;
		model.pushToDiscard(c);
		discardPile = c;
		break;
	case ServerMessageType.CHANGE_TURN:
		break;
	case ServerMessageType.DRAWPILE:
		break;
	case ServerMessageType.DRAWPILE_PLACE:
		break;
	case ServerMessageType.DRAWPILE_REJECT:
		break;
	case ServerMessageType.REVEAL:
		revealCard(message.playerNumber, message.row, message.col, message.card1);
		break;
	case ServerMessageType.DISCARD_SWAP:
		break;
	case ServerMessageType.COLUMN_REMOVAL:
		break;
	case ServerMessageType.LAST_TURN:
		break;
	case ServerMessageType.PLAYER_JOIN:
		playerJoined(message.playerNumber, message.name);
		break;
	case ServerMessageType.PLAYER_LEFT:
		playerLeft(message.playerNumber);
		break;
	case ServerMessageType.WAITING:
		break;
	case ServerMessageType.RECONNECTED:
		break;
	case ServerMessageType.CURRENT_SCORES:
		break;
	case ServerMessageType.WINNER:
		break;
	case ServerMessageType.YOUR_TURN:
		break;
	case ServerMessageType.CHOOSE_FLIP:
		beginFlipChoices();
		break;
	case ServerMessageType.YOU_ARE:
		localPlayerNumber = cast(ubyte) message.playerNumber;
		model.setPlayer(localPlayer, localPlayerNumber);
		break;
	case ServerMessageType.CARD:
		break;
	case ServerMessageType.GRID_CARDS:
		model.getPlayer(cast(ubyte) message.playerNumber).getGrid.setCards(message.cards);
		break;
	case ServerMessageType.IN_PROGRESS:
		break;
	case ServerMessageType.FULL:
		break;
	case ServerMessageType.NAME_TAKEN:
		break;
	case ServerMessageType.KICKED:
		break;
	case ServerMessageType.NEW_GAME:
		break;
	}
}

void playerJoined(int number, string name)
{
	ClientPlayer p = new ClientPlayer(name);
	p.setGrid( new ClientPlayerGrid!() );
	model.setPlayer(p, cast(ubyte) number);

	updateOppGridsEnabledStatus(model.numberOfPlayers);
	assignOpponentPositions();
}

void playerLeft(int number)
{
	model.setPlayer(null, cast(ubyte) number);

	updateOppGridsEnabledStatus(model.numberOfPlayers);
	assignOpponentPositions();
}

void beginDealing(int dealer)
{
	AbstractClientGrid[] clientGrids;
	clientGrids.reserve(model.numberOfPlayers);

	ubyte num = model.getNextPlayerAfter(cast(ubyte) dealer);
	ubyte first = num;

	do
	{
		clientGrids ~= cast(AbstractClientGrid) model.getPlayer(num).getGrid();
		num = model.getNextPlayerAfter(num);
	}
	while (num != first);

	dealAnim = new DealAnimation(draw_pile_position, clientGrids, 285.msecs,
	                             unknown_card, drawSound);
}

void beginFlipChoices()
{
	ClickablePlayerGrid grid = localPlayer.getGrid();
	auto revealedCount = grid.getCardsAsRange.count!(a => a.revealed);

	if (revealedCount < 2)
	{
		cardsRevealed = cast(ubyte) revealedCount;
		currentMode = UIMode.FLIP_ACTION;
		grid.setClickHandler((int row, int col)
		{
			writeln("click handler");

			if (cardsRevealed < 2)
			{
				++cardsRevealed;
				connection.send(ClientMessageType.FLIP, row, col);

				if (cardsRevealed == 2)
				{
					currentMode = UIMode.NO_ACTION;
					grid.setClickHandler( (int a, int b){}.asDelegate );
				}
			}
			else {
				throw new Error("invalid state");
			}
		});
	}
	else
	{
		currentMode = UIMode.NO_ACTION;
	}
}

void revealCard(int playerNumber, int row, int col, CardRank rank)
{
	Card c = new Card(rank);
	c.revealed = true;
	model.getPlayer(cast(ubyte) playerNumber)[row, col] = c;
}

void assignOpponentPositions()
{
	opponentGrids.each!( g => g.clearPlayer() );

	ubyte num = model.getNextPlayerAfter(localPlayerNumber);

	while (num != localPlayerNumber)
	{
		foreach (grid; opponentGrids)
		{
			if (grid.enabled && grid.player is null) {
				grid.setPlayer( cast(ClientPlayer) model.getPlayer(num) );
				break;
			}
		}
		num = model.getNextPlayerAfter(num);
	}
}

void updateOppGridsEnabledStatus(size_t numOfPlayers)
{
	if (numOfPlayers <= 2) {
		opponentGrids[0].enabled = false;
		opponentGrids[1].enabled = true;
		opponentGrids[2].enabled = false;
		opponentGrids[3].enabled = false;
	}
	else if (numOfPlayers == 3) {
		opponentGrids[0].enabled = false;
		opponentGrids[1].enabled = true;
		opponentGrids[2].enabled = true;
		opponentGrids[3].enabled = false;
	}
	else if (numOfPlayers == 4) {
		opponentGrids[0].enabled = true;
		opponentGrids[1].enabled = true;
		opponentGrids[2].enabled = true;
		opponentGrids[3].enabled = false;
	}
	else {
		opponentGrids.each!( a => a.enabled = true );
	}
}

enum NamePlacement
{
	ABOVE,
	BELOW
}

final class OpponentGrid
{
	enum offset_x = 205,
	     offset_y_above = -10,
	     offset_y_below = 418;

	private
	{
		Point position;
		ClientPlayer player;
		Label nameLabel;
		bool enabled;
	}

	this(Point position, NamePlacement placement, Font font, ref Renderer renderer)
	{
		this.position = position;

		Point labelPosition
			= position.offset(offset_x, placement == NamePlacement.ABOVE ? offset_y_above : offset_y_below);

		nameLabel = new Label("", font);
		//nameLabel.setColor(SDL_Color(255, 255, 255, 255));
		() @trusted { nameLabel.setRenderer(&renderer); } ();
		nameLabel.autoReRender = true;
		writeln("labelPosition= ", labelPosition.x, " ", labelPosition.y);
		nameLabel.enableAutoPosition(labelPosition.x, labelPosition.y, HorizontalPositionMode.CENTER,
			placement == NamePlacement.ABOVE ? VerticalPositionMode.BOTTOM : VerticalPositionMode.TOP);
	}

	void setPlayer(ClientPlayer player)
	{
		this.player = player;
		nameLabel.setText(player.getName);
		player.getGrid().setPosition(position);
	}

	void clearPlayer()
	{
		this.player = null;
		nameLabel.setText("");
	}

	void render(ref Renderer renderer)
	{
		if (player !is null) {
			player.getGrid().render(renderer);
		}
		nameLabel.draw(renderer);
	}
}

/* ---------------------------------- *
 *    Error notification functions    *
 * ---------------------------------- */

void showErrorDialog(string userMessage) @trusted nothrow
{
	SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "Skyjo - Error", userMessage.toStringz, null);
}

void showErrorDialog(Exception exc, string userMessage, Flag!"logToFile" log = No.logToFile) nothrow
{
	showErrorDialog(userMessage ~ ":\n\n" ~ exc.msg);

	if (log)
	{
		logFatalException(exc, userMessage);
	}
	else
	{
		writeError(exc, userMessage);
	}
}

void logFatalException(Throwable exc, string userMessage) @trusted nothrow
{
	writeError(exc, userMessage);

	try
	{
		import std.system : os;

		auto file = File("crash-report.txt", "w");
		file.writeln("Skyjo crash report\n---\n", Clock.currTime());
		file.writeln(version_str, " (", os, ")\n\n");
		file.writeln(userMessage, "\n---\n", exc);
	}
	catch (Exception e)
	{
	}
}

void writeError(Throwable exc, string userMessage) nothrow
{
	try
	{
		writeln(userMessage, "\n(", exc.msg, ")");
	}
	catch (Exception e)
	{
	}
}
