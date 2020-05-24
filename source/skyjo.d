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
enum drawn_card_position = Point(725, 47);

enum draw_pile_rect = Rectangle(draw_pile_position.x, draw_pile_position.y,
                                card_large_width, card_large_height);
enum discard_pile_rect = Rectangle(discard_pile_position.x, discard_pile_position.y,
                                   card_large_width, card_large_height);
enum drawn_card_rect = Rectangle(drawn_card_position.x, drawn_card_position.y,
                                 card_large_width, card_large_height);

enum total_audio_channels        = 8,
     num_reserved_audio_channels = 3;

enum anim_duration = 285.msecs;

Card unknown_card;

static this()
{
	unknown_card = new Card(CardRank.UNKNOWN);
	drawPile = new DrawPile(draw_pile_position);
	discardPile = new DiscardPile(discard_pile_position);
	drawnCard = new DrawnCard(drawn_card_position);
	opponentGrids = new OpponentGrid[4];
	socketSet = new SocketSet();
}

private
{
	GameModel model;
	SocketSet socketSet;
	ConnectionToServer connection;
	Font font;
	Texture disconnectedIcon;
	Sound dealSound;
	Sound flipSound;
	Sound discardSound;
	Sound drawSound;
	Sound yourTurnSound;
	Sound lastTurnSound;
	OpponentGrid[] opponentGrids;
	Background gameBackground;
	DrawPile drawPile;
	DiscardPile discardPile;
	DrawnCard drawnCard;
	Card opponentDrawnCard;
	Rectangle opponentDrawnCardRect;
	MoveAnimation moveAnim;
	DealAnimation dealAnim;
	void delegate() pendingAction = {};
	Point lastMousePosition;
	UIMode currentMode = UIMode.PRE_GAME;
	LocalPlayer localPlayer;
	ubyte localPlayerNumber;
	ubyte numCardsRevealed;
	ubyte numberOfAnimations;
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
	SWAP_CARD_ACTION,
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

	disconnectedIcon = renderer.loadTexture("assets/network-x.png");

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

	dealSound = loadWAV("assets/playcard.wav");
	flipSound = loadWAV("assets/cardPlace3.wav");
	discardSound = loadWAV("assets/cardShove1.wav");
	drawSound = loadWAV("assets/draw.wav");
	yourTurnSound = loadWAV("assets/cuckoo.wav");
	lastTurnSound = loadWAV("assets/UI_007.wav");
}

void masterLoop( ref Window window,
                 ref Renderer renderer,
                 ref bool quit,
                 ref KeyboardController controller )
{
	Socket socket = new TcpSocket();
	socket.connect(new InternetAddress("localhost", 7684));
	connection = new ConnectionToServer(socket);
	connection.send(ClientMessageType.JOIN, localPlayer.getName);
	socket.blocking = false;

	auto grid = localPlayer.getGrid();

	addObserver!"mouseDown"((event) {
		grid.mouseButtonDown(Point(event.x, event.y));
	});
	addObserver!"mouseUp"((event) {
		grid.mouseButtonUp(Point(event.x, event.y));
	});
	addObserver!"mouseMotion"((event) {
		grid.mouseMoved(Point(event.x, event.y));
	});

	addObserver!"mouseDown"((event) {
		drawPile.mouseButtonDown(Point(event.x, event.y));
	});
	addObserver!"mouseUp"((event) {
		drawPile.mouseButtonUp(Point(event.x, event.y));
	});
	addObserver!"mouseMotion"((event) {
		drawPile.mouseMoved(Point(event.x, event.y));
	});

	addObserver!"mouseDown"((event) {
		discardPile.mouseButtonDown(Point(event.x, event.y));
	});
	addObserver!"mouseUp"((event) {
		discardPile.mouseButtonUp(Point(event.x, event.y));
	});
	addObserver!"mouseMotion"((event) {
		discardPile.mouseMoved(Point(event.x, event.y));
	});

	addObserver!"mouseMotion"((event) {
		drawnCard.mouseMoved(Point(event.x, event.y));
	});

	grid.onClick = (int r, int c) {};

	mainLoop(window, renderer, quit, controller);
}

void mainLoop(ref Window window,
              ref Renderer renderer,
              ref bool quit,
              ref KeyboardController controller)
{
	MonoTime currentTime;
	MonoTime lastTime = MonoTime.currTime();

	while (! quit)
	{
		currentTime = MonoTime.currTime();
		auto elapsed = currentTime - lastTime;

		if ( elapsed < dur!"usecs"(16_600) )
		{
			sleepFor(dur!"usecs"(16_600) - elapsed);   // limits the framerate to ~60 fps
		}
		currentTime = MonoTime.currTime();
		elapsed = currentTime - lastTime;
		lastTime = currentTime;

		pollServer(connection);
		pollInputEvents(quit, controller);

		if (currentMode == UIMode.DEALING)
		{
			if ( dealAnim.process() ) {
				connection.send(ClientMessageType.READY);  // let the server know animation finished
				currentMode = UIMode.NO_ACTION;
			}
		}

		if ( moveAnim.process() )
		{
			if (numberOfAnimations > 0) {
				--numberOfAnimations;
			}

			if (numberOfAnimations == 0) {
				pendingAction();
				pendingAction = {};
			}
		}

		render(window, renderer);
	}
}

void render(ref Window window, ref Renderer renderer)
{
	ClickablePlayerGrid grid = localPlayer.getGrid;

	renderer.clear();
	renderer.setLogicalSize(0, 0);
	gameBackground.render(renderer, window);
	renderer.setLogicalSize(1920, 1080);

	bool windowHasFocus = window.testFlag(SDL_WINDOW_INPUT_FOCUS);
	applyCurrentMode(windowHasFocus);

	grid.render(renderer);
	opponentGrids.each!( opp => opp.render(renderer) );

	drawPile.render(renderer, windowHasFocus);
	discardPile.render(renderer, windowHasFocus);
	drawnCard.render(renderer, windowHasFocus);

	renderOppDrawnCard(renderer);

	moveAnim.render(renderer);

	if (currentMode == UIMode.DEALING) {
		dealAnim.render(renderer);
	}

	renderer.present();
}

void renderOppDrawnCard(ref Renderer renderer)
{
	if (opponentDrawnCard !is null)
	{
		opponentDrawnCard.draw(renderer, opponentDrawnCardRect);
	}
}

void applyCurrentMode(const bool windowHasFocus)
{
	ClickablePlayerGrid grid = localPlayer.getGrid;

	if (windowHasFocus)
	{
		if (currentMode == UIMode.FLIP_ACTION || currentMode == UIMode.MY_TURN_ACTION) {
			grid.setHighlightingMode(GridHighlightMode.SELECTION);
		}
		else if (currentMode == UIMode.SWAP_CARD_ACTION || currentMode == UIMode.DRAWN_CARD_ACTION) {
			grid.setHighlightingMode(GridHighlightMode.PLACEMENT);
		}
		else {
			grid.setHighlightingMode(GridHighlightMode.OFF);
		}
	}
	else {
		grid.setHighlightingMode(GridHighlightMode.OFF);
	}
}

void sleepFor(Duration d) @trusted @nogc
{
	Thread.getThis().sleep(d);
}

void pollServer(ConnectionToServer connection)
{
	socketSet.reset();
	socketSet.add(connection.socket);
	Socket.select(socketSet, null, null, dur!"usecs"(100));

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
			if (moveAnim.isFinished) {
				notifyObservers!"mouseDown"(e.button);
			}
		}
		else if (e.type == SDL_MOUSEBUTTONUP && e.button.button == SDL_BUTTON_LEFT)
		{
			if (moveAnim.isFinished) {
				notifyObservers!"mouseUp"(e.button);
			}
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
		flipOverFirstDiscardCard(message.card1);
		break;
	case ServerMessageType.CHANGE_TURN:
		currentMode = UIMode.OPPONENT_TURN;
		model.setPlayerCurrentTurn(message.playerNumber.to!ubyte);
		break;
	case ServerMessageType.DRAWPILE:
		opponentDrawsCard(message.playerNumber.to!ubyte);
		break;
	case ServerMessageType.DRAWPILE_PLACE:
		if (message.playerNumber == localPlayerNumber) {
			placeDrawnCard(localPlayer, message.row, message.col, message.card1, message.card2);
		}
		else {
			placeDrawnCard(model.getPlayer(message.playerNumber.to!ubyte),
			               message.row, message.col, message.card1, message.card2);
		}
		break;
	case ServerMessageType.DRAWPILE_REJECT:
		opponentDiscardsDrawnCard(message.playerNumber.to!ubyte, message.card1);
		break;
	case ServerMessageType.REVEAL:
		revealCard(message.playerNumber, message.row, message.col, message.card1);
		break;
	case ServerMessageType.DISCARD_SWAP:
		discardSwap(message.playerNumber, message.row, message.col, message.card1, message.card2);
		break;
	case ServerMessageType.COLUMN_REMOVAL:
		pendingAction = () => removeColumn(message.playerNumber.to!ubyte, message.col);
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
		playerDisconnected(message.playerNumber);
		break;
	case ServerMessageType.RECONNECTED:
		playerReconnected(message.playerNumber);
		break;
	case ServerMessageType.CURRENT_SCORES:
		break;
	case ServerMessageType.WINNER:
		break;
	case ServerMessageType.YOUR_TURN:
		model.setPlayerCurrentTurn(localPlayerNumber);
		beginOurTurn();
		break;
	case ServerMessageType.CHOOSE_FLIP:
		beginFlipChoices();
		break;
	case ServerMessageType.YOU_ARE:
		localPlayerNumber = message.playerNumber.to!ubyte;
		assert(localPlayer !is null);
		model.setPlayer(localPlayer, localPlayerNumber);
		break;
	case ServerMessageType.CARD:
		showDrawnCard(message.card1);
		break;
	case ServerMessageType.GRID_CARDS:
		model.getPlayer(message.playerNumber.to!ubyte).getGrid.setCards(message.cards);
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

void enterNoActionMode(UIMode mode = UIMode.NO_ACTION)
{
	currentMode = mode;
	localPlayer.getGrid.onClick = (a, b) {};
	drawPile.enabled = false;
	drawPile.onClick = {};
	discardPile.enabled = false;
	discardPile.onClick = {};
	drawnCard.enabled = false;
	drawnCard.onClick = {};
}

void playerJoined(int number, string name)
{
	ClientPlayer p = new ClientPlayer(name);
	p.setGrid( new ClientPlayerGrid!() );
	model.setPlayer(p, number.to!ubyte);

	updateOppGridsEnabledStatus(model.numberOfPlayers);
	assignOpponentPositions();
}

void playerLeft(int number)
{
	model.setPlayer(null, number.to!ubyte);

	updateOppGridsEnabledStatus(model.numberOfPlayers);
	assignOpponentPositions();
}

void playerDisconnected(int number)
{
	enterNoActionMode(UIMode.WAITING);
	(cast(ClientPlayer) model.getPlayer(number.to!ubyte)).disconnected = true;
}

void playerReconnected(int number)
{
	(cast(ClientPlayer) model.getPlayer(number.to!ubyte)).disconnected = false;
}

void beginDealing(int dealer)
{
	AbstractClientGrid[] clientGrids;
	clientGrids.reserve(model.numberOfPlayers);

	ubyte num = model.getNextPlayerAfter(cast(ubyte) dealer);
	immutable first = num;

	do
	{
		clientGrids ~= cast(AbstractClientGrid) model.getPlayer(num).getGrid();
		num = model.getNextPlayerAfter(num);
	}
	while (num != first);

	dealAnim = new DealAnimation(draw_pile_position, clientGrids, anim_duration,
	                             unknown_card, dealSound);
}

void beginFlipChoices()
{
	ClickablePlayerGrid grid = localPlayer.getGrid();
	immutable revealedCount = grid.getCardsAsRange.count!(a => a.revealed);

	if (revealedCount < 2)
	{
		numCardsRevealed = cast(ubyte) revealedCount;
		currentMode = UIMode.FLIP_ACTION;
		grid.onClick = (int row, int col)
		{
			if (grid.getCards[row][col].revealed) {
				return;
			}

			if (numCardsRevealed < 2)
			{
				++numCardsRevealed;
				connection.send(ClientMessageType.FLIP, row, col);
				flipSound.play();

				if (numCardsRevealed == 2) {
					enterNoActionMode();
				}
			}
			else
			{
				throw new Error("invalid state");
			}
		};
	}
	else
	{
		currentMode = UIMode.NO_ACTION;
	}
}

void beginOurTurn()
{
	currentMode = UIMode.MY_TURN_ACTION;

	ClickablePlayerGrid grid = localPlayer.getGrid();
	grid.onClick = (row, col) {
		if (grid.getCards[row][col].revealed) {
			return;
		}
		enterNoActionMode();
		connection.send(ClientMessageType.FLIP, row, col);
		flipSound.play();
	};

	drawPile.enabled = true;
	drawPile.onClick = {
		enterNoActionMode();
		connection.send(ClientMessageType.DRAW);
	};

	discardPile.enabled = true;
	discardPile.onClick = {
		enterNoActionMode();   // reset everything first
		currentMode = UIMode.SWAP_CARD_ACTION;
		discardPile.enabled = true;   // to enable the 'not interactable' highlight
		grid.onClick = (row, col) {
			enterNoActionMode();
			connection.send(ClientMessageType.SWAP, row, col);
		};
	};
}

void revealCard(int playerNumber, int row, int col, CardRank rank)
{
	Card c = new Card(rank);
	c.revealed = true;
	model.getPlayer(playerNumber.to!ubyte)[row, col] = c;

	if (currentMode == UIMode.OPPONENT_TURN) {
		flipSound.play();
	}
}

void flipOverFirstDiscardCard(CardRank rank)
{
	Card c = new Card(rank);
	c.revealed = true;

	if (currentMode != UIMode.NO_ACTION) {
		model.pushToDiscard(c);
		return;
	}

	moveAnim = MoveAnimation(unknown_card, draw_pile_rect, discard_pile_rect, 500.msecs);

	moveAnim.onFinished = {
		model.pushToDiscard(c);
		moveAnim = MoveAnimation.init;
		dealSound.play();
	};
}

void discardSwap(int playerNumber, int row, int col, CardRank cardTaken, CardRank cardThrown)
{
	Nullable!Card popped = model.popDiscardTopCard();

	if (popped.isNull || popped.get.rank != cardTaken) {
		popped = new Card(cardTaken);
		popped.get.revealed = true;
	}

	Player player = model.getPlayer(playerNumber.to!ubyte);
	const cardRect = (cast(AbstractClientGrid) player.getGrid).getCardDestination(row, col);

	moveAnim = MoveAnimation(popped.get, discard_pile_rect, cardRect, 750.msecs);
	moveAnim.onFinished = {
		dealSound.play();
		Card c;

		if (player[row, col].isNotNull && player[row, col].get.revealed
		    && player[row, col].get.rank == cardThrown)
		{
			c = player[row, col].get;
		}
		else
		{
			c = new Card(cardThrown);
			c.revealed = true;
		}

		moveAnim = MoveAnimation(c, cardRect, discard_pile_rect, 750.msecs);
		moveAnim.onFinished = {
			discardSound.play();
			model.pushToDiscard(c);
		};

		player[row, col] = popped.get;
	};
	numberOfAnimations = 2;
}

void showDrawnCard(CardRank rank)
{
	enterNoActionMode();
	drawSound.play();
	Card c = new Card(rank);
	c.revealed = true;

	moveAnim = MoveAnimation(c, draw_pile_rect, drawn_card_rect, anim_duration);
	moveAnim.onFinished = {
		drawnCard.drawnCard = c;
		drawnCard.enabled = true;
		discardPile.enabled = true;
		currentMode = UIMode.DRAWN_CARD_ACTION;

		localPlayer.getGrid.onClick = (int r, int c) {
			enterNoActionMode();
			connection.send(ClientMessageType.PLACE, r, c);
		};

		discardPile.onClick = {
			enterNoActionMode();
			connection.send(ClientMessageType.REJECT);
			discardDrawnCard();
		};
	};
}

void placeDrawnCard(T)(T player, int row, int col, CardRank takenRank, CardRank discardedRank)
{
	void assignTaken(ref Card drawn, ref Card taken)
	{
		if (drawn.rank == takenRank) {
			taken = drawn;
		}
		else {
			taken = new Card(takenRank);
		}
		drawn = null;
	}

	enterNoActionMode();
	Card taken;

	static if (is(T == LocalPlayer)) {
		assignTaken(drawnCard.drawnCard, taken);
		taken.revealed = true;
		alias start = drawn_card_rect;
	}
	else {
		assignTaken(opponentDrawnCard, taken);
		alias start = opponentDrawnCardRect;
	}

	const cardRect = (cast(AbstractClientGrid) player.getGrid).getCardDestination(row, col);
	moveAnim = MoveAnimation(taken, start, cardRect, 750.msecs);

	moveAnim.onFinished = {
		dealSound.play();
		Card c;

		if (player[row, col].isNotNull && player[row, col].get.revealed
		    && player[row, col].get.rank == discardedRank)
		{
			c = player[row, col].get;
		}
		else
		{
			c = new Card(discardedRank);
			c.revealed = true;
		}

		moveAnim = MoveAnimation(c, cardRect, discard_pile_rect, 750.msecs);
		moveAnim.onFinished = {
			discardSound.play();
			model.pushToDiscard(c);
		};

		static if (! is(T == LocalPlayer)) {
			taken.revealed = true;
		}
		player[row, col] = taken;
	};
	numberOfAnimations = 2;
}

void discardDrawnCard()
{
	Card c = drawnCard.drawnCard;
	drawnCard.drawnCard = null;

	moveAnim = MoveAnimation(c, drawn_card_rect, discard_pile_rect, 750.msecs);
	moveAnim.onFinished = {
		discardSound.play();
		model.pushToDiscard(c);
	};
}

void opponentDiscardsDrawnCard(ubyte playerNumber, CardRank rank)
{
	Card c = new Card(rank);
	opponentDrawnCard = null;

	const start = (cast(ClientPlayer) model.getPlayer(playerNumber)).getGrid.getDrawnCardDestination();

	moveAnim = MoveAnimation(c, start, discard_pile_rect, 750.msecs);
	moveAnim.onFinished = {
		discardSound.play();
		c.revealed = true;
		model.pushToDiscard(c);
	};
}

void opponentDrawsCard(ubyte playerNumber)
{
	enterNoActionMode();
	drawSound.play();

	const dest = (cast(ClientPlayer) model.getPlayer(playerNumber)).getGrid.getDrawnCardDestination();

	moveAnim = MoveAnimation(unknown_card, draw_pile_rect, dest, 750.msecs);
	moveAnim.onFinished = {
		opponentDrawnCard = unknown_card;
		opponentDrawnCardRect = dest;
	};
}

void removeColumn(ubyte playerNumber, int columnIndex)
{
	Player player = model.getPlayer(playerNumber);
	AbstractClientGrid grid = cast(AbstractClientGrid) player.getGrid();

	auto a = player[0, columnIndex];
	auto b = player[1, columnIndex];
	auto c = player[2, columnIndex];

	if (a.isNull || b.isNull || c.isNull) {
		return;
	}

	player[0, columnIndex] = null;
	moveAnim = MoveAnimation(a.get, grid.getCardDestination(0, columnIndex), discard_pile_rect, 750.msecs);
	moveAnim.onFinished = {
		dealSound.play();
		model.pushToDiscard(a.get);
		player[1, columnIndex] = null;

		moveAnim = MoveAnimation(b.get,
			grid.getCardDestination(1, columnIndex), discard_pile_rect, 750.msecs);
		moveAnim.onFinished = {
			dealSound.play();
			model.pushToDiscard(b.get);
			player[2, columnIndex] = null;

			moveAnim = MoveAnimation(c.get,
				grid.getCardDestination(2, columnIndex), discard_pile_rect, 750.msecs);
			moveAnim.onFinished = {
				dealSound.play();
				model.pushToDiscard(c.get);
			};
		};
	};
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

final class ClientPlayer : PlayerImpl!AbstractClientGrid
{
	bool disconnected;

	this(in char[] name)
	{
		super(name);
	}
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

		auto playerTurn = model.playerWhoseTurnItIs();

		if (player !is null && player.disconnected) {
			nameLabel.setColor(SDL_Color(255, 0, 0, 255));           // red

			Point labelPos = nameLabel.getPosition();
			int x = labelPos.x - disconnectedIcon.width - 5;
			renderer.renderCopy(disconnectedIcon, x, labelPos.y - 2);
		}
		else if (playerTurn.isNotNull && player is playerTurn.get) {
			nameLabel.setColor(SDL_Color(0, 0, 255, 255));           // blue
		}
		else {
			nameLabel.setColor(SDL_Color(0, 0, 0, 255));             // black
		}
		nameLabel.draw(renderer);
	}
}

abstract class ClickableCardPile : Clickable
{
	Point position;

	this(Point position)
	{
		this.setRectangle(Rectangle(position.x, position.y, card_large_width, card_large_height));
	}

	final void render(ref Renderer renderer, const bool windowHasFocus)
	{
		getShownCard().ifPresent!( c => c.draw(renderer, position, card_large_width, card_large_height,
			windowHasFocus && shouldBeHighlighted() ? highlightMode() : unhoveredHighlightMode()) );
	}

	mixin MouseUpActivation;

	abstract Nullable!(const Card) getShownCard();
	abstract Card.Highlight highlightMode();
	abstract Card.Highlight unhoveredHighlightMode();
}

final class DiscardPile : ClickableCardPile
{
	this(Point position)
	{
		super(position);
		this.position = position;
	}

	override Nullable!(const Card) getShownCard()
	{
		return model.getDiscardTopCard();
	}

	override Card.Highlight highlightMode()
	{
		if (currentMode == UIMode.SWAP_CARD_ACTION) {
			return Card.Highlight.SELECTED_HOVER;
		}
		else if (currentMode == UIMode.DRAWN_CARD_ACTION) {
			return Card.Highlight.PLACE;
		}
		else if (currentMode == UIMode.MY_TURN_ACTION) {
			return Card.Highlight.HOVER;
		}
		else {
			return Card.Highlight.OFF;
		}
	}

	override Card.Highlight unhoveredHighlightMode()
	{
		if (currentMode == UIMode.SWAP_CARD_ACTION) {
			return Card.Highlight.PLACE;
		}
		else {
			return Card.Highlight.OFF;
		}
	}
}

final class DrawPile : ClickableCardPile
{
	this(Point position)
	{
		super(position);
		this.position = position;
	}

	override Nullable!(const Card) getShownCard() const
	{
		return nullable(cast(const(Card)) unknown_card);
	}

	override Card.Highlight highlightMode()
	{
		if (currentMode == UIMode.MY_TURN_ACTION) {
			return Card.Highlight.HOVER;
		}
		else {
			return Card.Highlight.OFF;
		}
	}

	override Card.Highlight unhoveredHighlightMode()
	{
		return Card.Highlight.OFF;
	}
}

final class DrawnCard : ClickableCardPile
{
	Card drawnCard;

	this(Point position)
	{
		super(position);
		this.position = position;
	}

	override Nullable!(const Card) getShownCard() const
	{
		if (drawnCard !is null) {
			return drawnCard.nullable;
		}
		else {
			return (Nullable!(const Card)).init;
		}
	}

	override Card.Highlight highlightMode()
	{
		if (currentMode == UIMode.DRAWN_CARD_ACTION) {
			return Card.Highlight.SELECTED_HOVER;
		}
		else {
			return Card.Highlight.OFF;
		}
	}

	override Card.Highlight unhoveredHighlightMode()
	{
		if (currentMode == UIMode.DRAWN_CARD_ACTION) {
			return Card.Highlight.PLACE;
		}
		else {
			return Card.Highlight.OFF;
		}
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
