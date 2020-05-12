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

enum anim_duration = 285.msecs;

Card unknown_card;

static const foo = new Card(CardRank.UNKNOWN);

pragma(msg, typeof(foo));

static this()
{
	unknown_card = new Card(CardRank.UNKNOWN);
	drawPile = new DrawPile(draw_pile_position);
	discardPile = new DiscardPile(discard_pile_position);
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
	Sound dealSound;
	Sound flipSound;
	Sound discardSound;
	DrawPile drawPile;
	DiscardPile discardPile;
	MoveAnimation moveAnim;
	DealAnimation dealAnim;
	Point lastMousePosition;
	ubyte numCardsRevealed;
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

	grid.onClick = (int r, int c) {};

	mainLoop(window, renderer, quit, controller);
}

void mainLoop( ref Window window,
               ref Renderer renderer,
               ref bool quit,
               ref KeyboardController controller )
{
	MonoTime currentTime;
	MonoTime lastTime = MonoTime.currTime();

	while (! quit)
	{
		currentTime = MonoTime.currTime();
		auto elapsed = currentTime - lastTime;

		if ( elapsed < dur!"usecs"(16_600) )
		{
			sleepFor(dur!"usecs"(16_600) - elapsed);   // limits the framerate to about 60 fps
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

		moveAnim.process();

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

	applyCurrentMode( window.testFlag(SDL_WINDOW_INPUT_FOCUS) );

	grid.render(renderer);
	opponentGrids.each!( opp => opp.render(renderer) );

	drawPile.render(renderer);
	discardPile.render(renderer);

	moveAnim.render(renderer);

	if (currentMode == UIMode.DEALING) {
		dealAnim.render(renderer);
	}

	renderer.present();
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
		break;
	case ServerMessageType.DRAWPILE_PLACE:
		break;
	case ServerMessageType.DRAWPILE_REJECT:
		break;
	case ServerMessageType.REVEAL:
		revealCard(message.playerNumber, message.row, message.col, message.card1);
		break;
	case ServerMessageType.DISCARD_SWAP:
		discardSwap(message.playerNumber, message.row, message.col, message.card1, message.card2);
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
		model.setPlayerCurrentTurn(localPlayerNumber);
		beginOurTurn();
		break;
	case ServerMessageType.CHOOSE_FLIP:
		beginFlipChoices();
		break;
	case ServerMessageType.YOU_ARE:
		localPlayerNumber = cast(ubyte) message.playerNumber;
		assert(localPlayer !is null);
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

void enterNoActionMode()
{
	currentMode = UIMode.NO_ACTION;
	localPlayer.getGrid.onClick = (a, b) {};
	drawPile.enabled = false;
	drawPile.onClick = {};
	discardPile.enabled = false;
	discardPile.onClick = {};
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
	model.getPlayer(cast(ubyte) playerNumber)[row, col] = c;
}

void flipOverFirstDiscardCard(CardRank rank)
{
	Card c = new Card(rank);
	c.revealed = true;

	if (currentMode != UIMode.NO_ACTION) {
		model.pushToDiscard(c);
		return;
	}

	moveAnim = MoveAnimation(unknown_card, card_large_width, card_large_height,
	                         draw_pile_position, discard_pile_position, 500.msecs);

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

	Player player =  model.getPlayer(cast(ubyte) playerNumber);
	Point cardPos = (cast(AbstractClientGrid) player.getGrid).getCardDestination(row, col);

	moveAnim = MoveAnimation(popped.get, card_large_width, card_large_height,
	                         discard_pile_position, cardPos, 750.msecs);
	moveAnim.onFinished = {
		dealSound.play();
		Card c;

		if (player[row, col].isNotNull && player[row, col].get.revealed) {
			c = player[row, col].get;
		}
		else {
			c = new Card(cardThrown);
			c.revealed = true;
		}

		moveAnim = MoveAnimation(c, card_large_width, card_large_height,
			                     cardPos, discard_pile_position, 750.msecs);
		auto fn = {
			discardSound.play();
			model.pushToDiscard(c);
		};

		moveAnim.onFinished = fn;
		assert(moveAnim._onFinished is fn);

		player[row, col] = popped.get;
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

		auto playerTurn = model.playerWhoseTurnItIs();

		if (playerTurn.isNotNull && player is playerTurn.get) {
			nameLabel.setColor(SDL_Color(0, 0, 255, 255));
		}
		else {
			nameLabel.setColor(SDL_Color(0, 0, 0, 255));
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

	final void render(ref Renderer renderer)
	{
		getShownCard().ifPresent!( c => c.draw(renderer, position, card_large_width, card_large_height,
			shouldBeHighlighted() ? highlightMode() : unhoveredHighlightMode()) );
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
