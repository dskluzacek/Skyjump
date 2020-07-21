module client;
@safe:

import std.stdio;
import std.algorithm;
import std.string : strip;
import std.exception : enforce;
import std.array;
import std.typecons;
import std.functional;
import std.datetime : Clock;
import std.string : toStringz;
import std.socket;
import std.conv;
import std.container : DList;
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
import button;
import draganddrop;
import textfield;

enum window_title = "Skyjump";
enum version_str  = "pre-alpha";

enum connect_failed_str = "Failed to connect to server.";

enum draw_pile_position = Point(692, 15);
enum discard_pile_position = Point(1056, 15);
enum drawn_card_position = Point(725, 47);

enum draw_pile_rect = Rectangle(draw_pile_position.x, draw_pile_position.y,
                                card_large_width, card_large_height);
enum discard_pile_rect = Rectangle(discard_pile_position.x, discard_pile_position.y,
                                   card_large_width, card_large_height);
enum drawn_card_rect = Rectangle(drawn_card_position.x, drawn_card_position.y,
                                 card_large_width, card_large_height);

enum cancel_button_dims = Rectangle(1248, 215, 120, 40);
enum connect_button_dims = Rectangle(880, 620, 160, 40);

enum name_field_dims = Rectangle(777, 490, 550, 50);
enum server_field_dims = Rectangle(777, 550, 550, 50);

enum total_audio_channels        = 8,
     num_reserved_audio_channels = 3;

enum connect_timeout = 12.seconds;

enum anim_duration = 285.msecs;
enum dragged_anim_speed = 0.728f;  // pixels per ms

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
	Font nameFont;
	Font largeFont;
	Font mediumFont;
	Font smallFont;
	Font uiFont;
	Font textFieldFont;
	Texture disconnectedIcon;
	Sound dealSound;
	Sound flipSound;
	Sound discardSound;
	Sound drawSound;
	Sound yourTurnSound;
	Sound lastTurnSound;
	SDL_Cursor* arrowCursor;
	SDL_Cursor* iBeamCursor;
	OpponentGrid[] opponentGrids;
	Background gameBackground;
	DrawPile drawPile;
	DiscardPile discardPile;
	DrawnCard drawnCard;
	Button cancelButton;
	Button connectButton;
	Card opponentDrawnCard;
	Rectangle opponentDrawnCardRect;
	Label lastTurnLabel1;
	Label lastTurnLabel2;
	Label serverFieldLabel;
	Label nameFieldLabel;
	Label feedbackLabel;
	MoveAnimation moveAnim;
	DealAnimation dealAnim;
	DList!(void delegate()) pendingActions;
	MonoTime yourTurnSoundTimerStart;
	MonoTime lastTurnSoundTimerStart;
	MonoTime connectAttemptTimerStart;
	TextComponent[] textComponents;
	TextField nameTextField;
	TextField serverTextField;
	Focusable focusedItem;
	FocusType itemFocusType = FocusType.NONE;
	Point lastMousePosition;
	UIMode currentMode = UIMode.CONNECT;
	LocalPlayer localPlayer;
	PlayerLabel localPlayerLabel;
	ubyte localPlayerNumber;
	ubyte numCardsRevealed;
	ubyte numberOfAnimations;
}

enum UIMode
{
	CONNECT,
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

void main() @system
{
	try {
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
		showErrorDialog("An error occurred and Skyjump is closing.");
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

		SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "linear");
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
		1200, 675,
		SDL_WINDOW_HIDDEN
//		| SDL_WINDOW_MAXIMIZED
		| SDL_WINDOW_RESIZABLE );

		renderer = window.createRenderer( SDL_RENDERER_ACCELERATED
		                                  | SDL_RENDERER_PRESENTVSYNC );

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
	uiFont = openFont("assets/Metropolis-ExtraBold.ttf", 26);
	largeFont = openFont("assets/Metropolis-ExtraBold.ttf", 42);
	mediumFont = openFont("assets/Metropolis-Medium.ttf", 32);
	smallFont = openFont("assets/Metropolis-Medium.ttf", 24);
	nameFont = openFont("assets/Metropolis-SemiBold.ttf", 37);
	textFieldFont = openFont("assets/RobotoCondensed-Regular.ttf", 36);

	localPlayer = new LocalPlayer();

	localPlayerLabel = new PlayerLabel(Point(1354, 1060), HorizontalPositionMode.LEFT,
	                                   VerticalPositionMode.BOTTOM, nameFont, renderer);

	cancelButton = new Button(cancel_button_dims, "Cancel", uiFont, renderer);
	cancelButton.visible = false;

	auto clickableGrid = new ClickablePlayerGrid(Point(586, 320));
	clickableGrid.setFocusables(drawPile, discardPile, cancelButton);
	localPlayer.setGrid(clickableGrid);

	cancelButton.nextTab = clickableGrid;
	cancelButton.nextDown = clickableGrid;

	arrowCursor = createCursor(SDL_SYSTEM_CURSOR_ARROW);
	iBeamCursor = createCursor(SDL_SYSTEM_CURSOR_IBEAM);

	nameTextField = new TextField(textFieldFont, name_field_dims, 4, arrowCursor, iBeamCursor);
	nameTextField.maxTextLength = MAX_NAME_LENGTH;
	serverTextField = new TextField(textFieldFont, server_field_dims, 4, arrowCursor, iBeamCursor);
	serverTextField.maxTextLength = 20;
	serverTextField.setText("localhost", renderer);
	textComponents = [nameTextField, serverTextField];

	connectButton = new Button(connect_button_dims, "Connect", uiFont, renderer);
	connectButton.enabled = true;
	nameTextField.onEnter = connectButton;
	serverTextField.onEnter = connectButton;

	nameTextField.nextDown = serverTextField;
	nameTextField.nextTab = serverTextField;
	serverTextField.nextUp = nameTextField;
	serverTextField.nextDown = connectButton;
	serverTextField.nextTab = connectButton;
	connectButton.nextUp = serverTextField;
	connectButton.nextTab = nameTextField;

	feedbackLabel = new Label("", smallFont);
	() @trusted { feedbackLabel.setRenderer(&renderer); } ();
	feedbackLabel.autoReRender = true;
	feedbackLabel.enableAutoPosition(960, connect_button_dims.y + connect_button_dims.h + 50,
	                                 HorizontalPositionMode.CENTER, VerticalPositionMode.TOP);

	nameFieldLabel = new Label("Your name: ", mediumFont);
	nameFieldLabel.setPosition(name_field_dims.x, name_field_dims.y + name_field_dims.h / 2,
	                           HorizontalPositionMode.RIGHT, VerticalPositionMode.CENTER);
	nameFieldLabel.renderText(renderer);

	serverFieldLabel = new Label("Server address: ", mediumFont);
	serverFieldLabel.setPosition(server_field_dims.x, server_field_dims.y + server_field_dims.h / 2,
	                             HorizontalPositionMode.RIGHT, VerticalPositionMode.CENTER);
	serverFieldLabel.renderText(renderer);

	lastTurnLabel1 = new Label("Last", largeFont);
	lastTurnLabel1.setPosition(960, 135, HorizontalPositionMode.CENTER, VerticalPositionMode.BOTTOM);
	lastTurnLabel1.renderText(renderer);
	lastTurnLabel1.setVisible(false);

	lastTurnLabel2 = new Label("Turn!", largeFont);
	lastTurnLabel2.setPosition(960, 135, HorizontalPositionMode.CENTER, VerticalPositionMode.TOP);
	lastTurnLabel2.renderText(renderer);
	lastTurnLabel2.setVisible(false);

	opponentGrids[0] = new OpponentGrid(Point(40, 580), NamePlacement.ABOVE, nameFont, renderer);
	opponentGrids[1] = new OpponentGrid(Point(40, 40), NamePlacement.BELOW, nameFont, renderer);
	opponentGrids[2] = new OpponentGrid(Point(1464, 40), NamePlacement.BELOW, nameFont, renderer);
	opponentGrids[3] = new OpponentGrid(Point(1464, 580), NamePlacement.ABOVE, nameFont, renderer);

	gameBackground = new Background( renderer.loadTexture("assets/wood.png") );

	disconnectedIcon = renderer.loadTexture("assets/network-x.png");

	Card.setTexture(CardRank.NEGATIVE_TWO, renderer.loadTexture("assets/-2.png") );
	Card.setTexture(CardRank.NEGATIVE_ONE, renderer.loadTexture("assets/-1.png") );
	Card.setTexture(CardRank.ZERO, renderer.loadTexture("assets/0.png") );
	Card.setTexture(CardRank.ONE, renderer.loadTexture("assets/1.png") );
	Card.setTexture(CardRank.TWO, renderer.loadTexture("assets/2.png") );
	Card.setTexture(CardRank.THREE, renderer.loadTexture("assets/3.png") );
	Card.setTexture(CardRank.FOUR, renderer.loadTexture("assets/4.png") );
	Card.setTexture(CardRank.FIVE, renderer.loadTexture("assets/5.png") );
	Card.setTexture(CardRank.SIX, renderer.loadTexture("assets/6.png") );
	Card.setTexture(CardRank.SEVEN, renderer.loadTexture("assets/7.png") );
	Card.setTexture(CardRank.EIGHT, renderer.loadTexture("assets/8.png") );
	Card.setTexture(CardRank.NINE, renderer.loadTexture("assets/9.png") );
	Card.setTexture(CardRank.TEN, renderer.loadTexture("assets/10.png") );
	Card.setTexture(CardRank.ELEVEN, renderer.loadTexture("assets/11.png") );
	Card.setTexture(CardRank.TWELVE, renderer.loadTexture("assets/12.png") );
	Card.setTexture(CardRank.UNKNOWN, renderer.loadTexture("assets/back-grad.png") );

	dealSound = loadWAV("assets/playcard.wav");
	flipSound = loadWAV("assets/cardPlace3.wav");
	discardSound = loadWAV("assets/cardShove1.wav");
	drawSound = loadWAV("assets/draw.wav");
	yourTurnSound = loadWAV("assets/cuckoo.wav");
	lastTurnSound = loadWAV("assets/UI_007.wav");
}

SDL_Cursor* createCursor(SDL_SystemCursor c) @trusted nothrow @nogc
{
	return SDL_CreateSystemCursor(c);
}

void masterLoop(ref Window window,
                ref Renderer renderer,
                ref bool quit,
                ref KeyboardController controller)
{
	connectButton.onClick = (&connect).asDelegate;

	auto grid = localPlayer.getGrid();
	grid.onClick = (int r, int c) {};

	addClickable(grid);
	addClickable(drawPile);
	addClickable(discardPile);
	addClickable(cancelButton);
	addClickable(connectButton);
	addClickable(drawnCard);
	addClickable(nameTextField);
	addClickable(serverTextField);

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

		pollServer();
		pollInputEvents(quit, controller, renderer);

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

			while (numberOfAnimations == 0 && ! pendingActions.empty) {
				( pendingActions.front() )();
				pendingActions.removeFront();
			}
		}

		if (lastTurnSoundTimerStart != MonoTime.init
		    && MonoTime.currTime() - lastTurnSoundTimerStart > 1000.msecs)
		{
			lastTurnSound.play();
			lastTurnSoundTimerStart = MonoTime.init;

			if (yourTurnSoundTimerStart != MonoTime.init) {
				yourTurnSoundTimerStart = MonoTime.currTime();
			}
		}

		if (yourTurnSoundTimerStart != MonoTime.init
		    && MonoTime.currTime() - yourTurnSoundTimerStart > 1000.msecs)
		{
			yourTurnSound.play();
			yourTurnSoundTimerStart = MonoTime.init;
		}

		render(window, renderer);
	}
}

void render(ref Window window, ref Renderer renderer)
{
	renderer.clear();
	renderer.setLogicalSize(0, 0);
	gameBackground.render(renderer, window);
	renderer.setLogicalSize(1920, 1080);

	bool windowHasFocus = window.testFlag(SDL_WINDOW_INPUT_FOCUS);
	applyCurrentMode(windowHasFocus);

	ClickablePlayerGrid grid = localPlayer.getGrid;
	grid.render(renderer);
	opponentGrids.each!( opp => opp.render(renderer) );

	localPlayerLabel.render(renderer);
	lastTurnLabel1.draw(renderer);
	lastTurnLabel2.draw(renderer);

	cancelButton.draw(renderer);

	nameFieldLabel.draw(renderer);
	serverFieldLabel.draw(renderer);
	connectButton.draw(renderer);
	feedbackLabel.draw(renderer);

	nameTextField.draw(renderer);
	serverTextField.draw(renderer);

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

void connect()
{
	focusReset();

	string name = nameTextField.getText();
	string address = serverTextField.getText();

	if ( name.strip() == "" ) {
		feedbackLabel.setText("Name cannot be blank.");
		return;
	}
	else if ( address.strip() == "" ) {
		feedbackLabel.setText("Server address cannot be blank.");
		return;
	}

	feedbackLabel.setText("");
	localPlayer.setName(name);

	Socket socket;

	try {
		auto addr = new InternetAddress(address, 7684);
		socket = new TcpSocket();
		socket.blocking = false;
		socket.connect(addr);
		connection = new ConnectionToServer(socket);
		connectAttemptTimerStart = MonoTime.currTime();
		connectButton.enabled = false;
	}
	catch (SocketException e) {
		feedbackLabel.setText(connect_failed_str);

		if (socket) {
			socket.close();
		}
		connection = null;
	}
}

void pollServer()
{
	void resetConnection()
	{
		connection.socket.close();
		connection = null;

		if (currentMode == UIMode.CONNECT) {
			connectButton.enabled = true;
		}
		else {
			enterConnectMode();
		}
	}

	if (connection is null) {
		return;
	}
	socketSet.reset();
	socketSet.add(connection.socket);

	if (connection.isConnected)
	{
		Nullable!ServerMessage message;

		try {
			Socket.select(socketSet, null, null, dur!"usecs"(100));
			message = connection.poll(socketSet);

			message.ifPresent!((message) {
				if (currentMode == UIMode.CONNECT) {
					leaveConnectMode();
				}

				bool stop = handleMessage(message);

				if (stop) {
					resetConnection();
					return;
				}
			});
		}
		catch (JoinException e) {
			feedbackLabel.setText(connect_failed_str);
			resetConnection();
			return;
		}
		catch (SocketReadException e) {
			feedbackLabel.setText("The connection to the server was lost.");
			resetConnection();
			return;
		}
	}
	else
	{
		Socket.select(null, socketSet, null, dur!"usecs"(100));
		connection.checkConnected(socketSet);

		if (connection.isConnected)
		{
			connection.send(ClientMessageType.JOIN, localPlayer.getName);
			return;
		}
	}
	assert(connectAttemptTimerStart != MonoTime.init);

	if (connection !is null && ! connection.isDataReceived
	    && MonoTime.currTime() - connectAttemptTimerStart > connect_timeout)
	{
		feedbackLabel.setText(connect_failed_str);
		resetConnection();
	}
}

/**
 * Processes input events from the SDL event queue
 */
void pollInputEvents(ref bool quit, ref KeyboardController controller, ref Renderer renderer)
{
	@trusted auto poll(ref SDL_Event ev)
	{
		return SDL_PollEvent(&ev);
	}

	SDL_Event e;
	auto textWidget = textComponents.filter!(a => a.acceptingTextInput);

	while ( poll(e) )
	{
		// If user closes the window:
		if (e.type == SDL_QUIT)
		{
			quit = true;
			break;
		}
		else if (e.type == SDL_TEXTINPUT)
		{
			if (! textWidget.empty)
			{
				textWidget.front.inputEvent(e.text, renderer);
			}
		}
		else if (e.type == SDL_KEYDOWN)
		{
			if ( ! textWidget.empty && textWidget.front.keyboardEvent(e.key, renderer) )
			{
				continue;
			}

			if ((e.key.keysym.scancode == SDL_SCANCODE_LEFT || e.key.keysym.scancode == SDL_SCANCODE_RIGHT
			    || e.key.keysym.scancode == SDL_SCANCODE_UP || e.key.keysym.scancode == SDL_SCANCODE_DOWN
			    || e.key.keysym.sym == SDLK_TAB) && ! e.key.repeat)
			{
				focusKeyPress(e.key.keysym.scancode);
			}
			else if ((e.key.keysym.scancode == SDL_SCANCODE_SPACE || e.key.keysym.scancode == SDL_SCANCODE_RETURN
			         || e.key.keysym.scancode == SDL_SCANCODE_KP_ENTER) && ! e.key.repeat)
			{
				focusActivate();
			}
			else
			{
				controller.handleEvent(e.key); // e.key is SDL_KeyboardEvent field in SDL_Event
			}
		}
		else if (e.type == SDL_MOUSEMOTION)
		{
			lastMousePosition.x = e.motion.x;
			lastMousePosition.y = e.motion.y;

			focusMouseMoved();
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

void focusKeyPress(SDL_Scancode code)
{
	if (focusedItem is null)
	{
		Focusable item;

		if (currentMode == UIMode.CONNECT) {
			item = nameTextField;
		}
		else {
			item = localPlayer.getGrid;
		}

		if ( ! item.focusEnabled() ) {
			return;
		}

		focusedItem = item;
		focusedItem.receiveFocus();
		setFocusType(FocusType.STRONG);
	}
	else
	{
		Focusable previous = focusedItem;

		switch (code)
		{
		case SDL_SCANCODE_TAB:
			focusedItem = focusedItem.nextTab();
			break;
		case SDL_SCANCODE_LEFT:
			focusedItem = focusedItem.nextLeft();
			break;
		case SDL_SCANCODE_UP:
			focusedItem = focusedItem.nextUp();
			break;
		case SDL_SCANCODE_RIGHT:
			focusedItem = focusedItem.nextRight();
			break;
		case SDL_SCANCODE_DOWN:
			focusedItem = focusedItem.nextDown();
			break;
		default:
			assert(0);
		}
		assert(focusedItem.focusEnabled);

		if (previous !is focusedItem) {
			previous.loseFocus();
		}

		if (code == SDL_SCANCODE_TAB) {
			focusedItem.receiveFocus();
		}
		else {
			focusedItem.receiveFocusFrom(previous);
		}
		setFocusType(FocusType.STRONG);
	}
}

void focusActivate()
{
	if (itemFocusType == FocusType.STRONG) {
		focusedItem.activate();
	}
}

void focusMouseMoved()
{
	if (focusedItem !is null) {
		focusedItem.cursorMoved();
	}

	if (itemFocusType == FocusType.STRONG) {
		setFocusType(FocusType.WEAK);
	}
}

void focusReset()
{
	if (focusedItem !is null) {
		focusedItem.loseFocus();
		focusedItem = null;
	}
	setFocusType(FocusType.NONE);
}

void setFocusType(FocusType type)
{
	itemFocusType = type;
	localPlayer.getGrid.windowFocusNotify(type);
	cancelButton.windowFocusNotify(type);
	connectButton.windowFocusNotify(type);
}

mixin Observable!("mouseMotion", SDL_MouseMotionEvent);
mixin Observable!("mouseDown", SDL_MouseButtonEvent);
mixin Observable!("mouseUp", SDL_MouseButtonEvent);

void addClickable(Clickable c)
{
	addObserver!"mouseDown"((SDL_MouseButtonEvent event) {
		c.mouseButtonDown(Point(event.x, event.y));
	});
	addObserver!"mouseUp"((SDL_MouseButtonEvent event) {
		c.mouseButtonUp(Point(event.x, event.y));
	});
	addObserver!"mouseMotion"((SDL_MouseMotionEvent event) {
		c.mouseMoved(Point(event.x, event.y));
	});
}

bool handleMessage(ServerMessage message)
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
		pendingActions.insertBack({
			if (message.playerNumber == localPlayerNumber) {
				placeDrawnCard(localPlayer, message.row, message.col, message.card1, message.card2);
			}
			else {
				placeDrawnCard(model.getPlayer(message.playerNumber.to!ubyte),
							   message.row, message.col, message.card1, message.card2);
			}
		});
		break;
	case ServerMessageType.DRAWPILE_REJECT:
		pendingActions.insertBack(() => opponentDiscardsDrawnCard(message.playerNumber.to!ubyte, message.card1));
		break;
	case ServerMessageType.REVEAL:
		revealCard(message.playerNumber, message.row, message.col, message.card1);
		break;
	case ServerMessageType.DISCARD_SWAP:
		discardSwap(message.playerNumber, message.row, message.col, message.card1, message.card2);
		break;
	case ServerMessageType.COLUMN_REMOVAL:
		pendingActions.insertBack(() => removeColumn(message.playerNumber.to!ubyte, message.col));
		break;
	case ServerMessageType.LAST_TURN:
		model.setPlayerOut(message.playerNumber.to!ubyte);
		lastTurnLabel1.setVisible(true);
		lastTurnLabel2.setVisible(true);
		lastTurnSoundTimerStart = MonoTime.currTime();
		break;
	case ServerMessageType.PLAYER_JOIN:
		playerJoined(message.playerNumber, message.name);
		break;
	case ServerMessageType.PLAYER_LEFT:
		playerLeft(message.playerNumber);
		if (currentMode != UIMode.PRE_GAME && model.numberOfPlayers == 1) {
			feedbackLabel.setText("All of the other players left.");
			return true;
		}
		break;
	case ServerMessageType.WAITING:
		pendingActions.insertBack(() => playerDisconnected(message.playerNumber));
		break;
	case ServerMessageType.RECONNECTED:
		playerReconnected(message.playerNumber);
		break;
	case ServerMessageType.CURRENT_SCORES:
		lastTurnLabel1.setVisible(false);
		lastTurnLabel2.setVisible(false);
		updateScores(message.scores);
		break;
	case ServerMessageType.WINNER:
		break;
	case ServerMessageType.YOUR_TURN:
		pendingActions.insertBack( asDelegate({
			model.setPlayerCurrentTurn(localPlayerNumber);
			beginOurTurn();
		}) );
		break;
	case ServerMessageType.RESUME_DRAW:
		pendingActions.insertBack( asDelegate({
			enforce!ProtocolException(drawnCard.drawnCard !is null);
			enterDrawnCardActionMode();
			yourTurnSoundTimerStart = MonoTime.currTime();
		}) );
		break;
	case ServerMessageType.CHOOSE_FLIP:
		beginFlipChoices();
		break;
	case ServerMessageType.YOU_ARE:
		localPlayerNumber = message.playerNumber.to!ubyte;
		enforce!ProtocolException(localPlayer !is null);
		model.setPlayer(localPlayer, localPlayerNumber);
		break;
	case ServerMessageType.CARD:
		showDrawnCard(message.card1);
		break;
	case ServerMessageType.GRID_CARDS:
		pendingActions.insertBack({
			model.getPlayer(message.playerNumber.to!ubyte).getGrid.setCards(message.cards);
		});
		break;
	case ServerMessageType.IN_PROGRESS:
		feedbackLabel.setText("Couldn't join - game already in progress on this server.");
		return true;
	case ServerMessageType.FULL:
		feedbackLabel.setText("Couldn't join - this game is full.");
		return true;
	case ServerMessageType.NAME_TAKEN:
		feedbackLabel.setText("That name is already taken in this game - please try something else.");
		return true;
	case ServerMessageType.KICKED:
		feedbackLabel.setText("You have been kicked from the game.");
		return true;
	case ServerMessageType.NEW_GAME:
		break;
	}

	return false;
}

void leaveConnectMode(UIMode mode = UIMode.PRE_GAME)
{
	currentMode = mode;
	focusReset();
	localPlayerLabel.setPlayer(localPlayer);
	nameTextField.visible = false;
	nameFieldLabel.setVisible(false);
	serverTextField.visible = false;
	serverFieldLabel.setVisible(false);
	connectButton.visible = false;
	feedbackLabel.setVisible(false);
}

void enterConnectMode()
{
	enterNoActionMode(UIMode.CONNECT);

	moveAnim.cancel();
	pendingActions.clear();

	nameTextField.visible = true;
	nameTextField.enabled = true;
	nameFieldLabel.setVisible(true);
	serverTextField.visible = true;
	serverTextField.enabled = true;
	serverFieldLabel.setVisible(true);
	connectButton.visible = true;
	connectButton.enabled = true;
	feedbackLabel.setVisible(true);

	model.reset();
	writeln(model.numberOfPlayers);
	writeln(model.getDiscardTopCard);

	localPlayer.getGrid.clear();
	localPlayerLabel.clearPlayer();
	opponentGrids.each!( g => g.clearPlayer() );
	opponentDrawnCard = null;
	drawnCard.drawnCard = null;
	updateOppGridsEnabledStatus(0);
}

void enterNoActionMode(UIMode mode = UIMode.NO_ACTION)
{
	currentMode = mode;
	focusReset();
	localPlayer.getGrid.onClick = (a, b) {};
	drawPile.enabled = false;
	drawPile.onClick = {};
	discardPile.enabled = false;
	discardPile.dragEnabled = false;
	discardPile.onClick = {};
	drawnCard.enabled = false;
	drawnCard.dragEnabled = false;
	drawnCard.onClick = {};
	cancelButton.enabled = false;
	cancelButton.visible = false;
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

	if (model.getPlayerCurrentTurn == number) {
		opponentDrawnCard = null;
	}

	updateOppGridsEnabledStatus(model.numberOfPlayers);
	assignOpponentPositions();
}

void playerDisconnected(int number)
{
	yourTurnSoundTimerStart = MonoTime.init;   // suppress "your turn" sound
	enterNoActionMode(UIMode.WAITING);
	(cast(ClientPlayer) model.getPlayer(number.to!ubyte)).disconnected = true;
}

void playerReconnected(int number)
{
	(cast(ClientPlayer) model.getPlayer(number.to!ubyte)).disconnected = false;
}

void beginDealing(int dealer)
{
	if (model.getPlayerOut.isNotNull) {
		model.nextHand();
	}

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
	yourTurnSoundTimerStart = MonoTime.currTime();
	startTurn();
}

void startTurn()
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
		discardPile.dragEnabled = true;
		grid.onClick = (row, col) {
			enterNoActionMode();
			connection.send(ClientMessageType.SWAP, row, col);
		};
		cancelButton.visible = true;
		cancelButton.enabled = true;
		cancelButton.onClick = {
			enterNoActionMode();
			startTurn();
		};
	};

	discardPile.dragEnabled = true;
	discardPile.setTargets([grid]);
	grid.onDrop = (row, col) {
		enterNoActionMode();
		connection.send(ClientMessageType.SWAP, row, col);
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
	numberOfAnimations = 1;
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
	Rectangle originRect;
	Duration animDuration;

	if ( discardPile.isDropped() ) {
		originRect = discard_pile_rect.offset( discardPile.positionAdjustment()[] );
		animDuration = (cast(long) (distance(originRect, cardRect) / dragged_anim_speed)).msecs;
	}
	else {
		originRect = discard_pile_rect;
		animDuration = 750.msecs;
	}

	moveAnim = MoveAnimation(popped.get, originRect, cardRect, animDuration);
	moveAnim.onFinished = {
		discardPile.reset();  // reset drag-and-drop state
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

void enterDrawnCardActionMode()
{
	drawnCard.enabled = true;
	discardPile.enabled = true;
	currentMode = UIMode.DRAWN_CARD_ACTION;

	drawnCard.dragEnabled = true;
	drawnCard.setTargets([cast(DragAndDropTarget) localPlayer.getGrid, discardPile]);

	auto placeHandler = asDelegate((int r, int c) {
		enterNoActionMode();
		connection.send(ClientMessageType.PLACE, r, c);
	});
	localPlayer.getGrid.onClick = placeHandler;
	localPlayer.getGrid.onDrop = placeHandler;

	auto discardHandler = asDelegate({
		enterNoActionMode();
		connection.send(ClientMessageType.REJECT);
		discardDrawnCard();
	});
	discardPile.onClick = discardHandler;
	discardPile.onDrop = discardHandler;
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
		enterDrawnCardActionMode();
	};
	numberOfAnimations = 1;
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
	const cardRect = (cast(AbstractClientGrid) player.getGrid).getCardDestination(row, col);
	Card taken;
	Rectangle originRect;
	Duration animDuration;

	static if (is(T == LocalPlayer)) {
		assignTaken(drawnCard.drawnCard, taken);
		taken.revealed = true;

		if ( drawnCard.isDropped() ) {
			originRect = drawn_card_rect.offset( drawnCard.positionAdjustment()[] );
			animDuration = (cast(long) (distance(originRect, cardRect) / dragged_anim_speed)).msecs;
		}
		else {
			originRect = drawn_card_rect;
			animDuration = 750.msecs;
		}
	}
	else {
		assignTaken(opponentDrawnCard, taken);
		originRect = opponentDrawnCardRect;
		animDuration = 750.msecs;
	}

	moveAnim = MoveAnimation(taken, originRect, cardRect, animDuration);
	moveAnim.onFinished = {
		drawnCard.reset();
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

	Rectangle originRect;
	Duration animDuration;

	if ( drawnCard.isDropped() ) {
		originRect = drawn_card_rect.offset( drawnCard.positionAdjustment()[] );
		animDuration = (cast(long) (distance(originRect, discard_pile_rect) / dragged_anim_speed)).msecs;
	}
	else {
		originRect = drawn_card_rect;
		animDuration = 750.msecs;
	}

	moveAnim = MoveAnimation(c, originRect, discard_pile_rect, animDuration);
	moveAnim.onFinished = {
		drawnCard.reset();
		discardSound.play();
		model.pushToDiscard(c);
	};
	numberOfAnimations = 1;
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
	numberOfAnimations = 1;
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
	numberOfAnimations = 1;
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
	numberOfAnimations = 3;
}

void updateScores(int[ubyte] scores)
{
	foreach (key, value; scores)
	{
		model.getPlayer(key).setScore(value);
	}
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

final class PlayerLabel
{
	Player player;
	Label nameLabel;

	this(Point position, HorizontalPositionMode hMode,
	     VerticalPositionMode vMode, Font font, ref Renderer renderer)
	{
		nameLabel = new Label("", font);
		() @trusted { nameLabel.setRenderer(&renderer); } ();
		nameLabel.autoReRender = true;
		nameLabel.enableAutoPosition(position.x, position.y, hMode, vMode);
	}

	void setPlayer(Player player)
	{
		this.player = player;
		nameLabel.setText(player.getName);
	}

	void clearPlayer()
	{
		this.player = null;
		nameLabel.setText("");
	}

	void render(ref Renderer renderer, bool overrideColor = false)
	{
		if (player !is null && currentMode != UIMode.PRE_GAME) {
			nameLabel.setText(player.getName ~ " (" ~ player.getScore.to!string ~ ')');
		}
		auto playerTurn = model.playerWhoseTurnItIs();

		if (overrideColor) {
			// do nothing
		}
		else if (playerTurn.isNotNull && player is playerTurn.get && currentMode != UIMode.PRE_GAME
		         && currentMode != UIMode.DEALING && currentMode != UIMode.FLIP_ACTION)
		{
			nameLabel.setColor(SDL_Color(0, 0, 255, 255));           // blue
		}
		else {
			nameLabel.setColor(SDL_Color(0, 0, 0, 255));             // black
		}
		nameLabel.draw(renderer);
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
		PlayerLabel playerLabel;
		bool enabled;
	}

	this(Point position, NamePlacement placement, Font font, ref Renderer renderer)
	{
		this.position = position;

		Point labelPosition
			= position.offset(offset_x, placement == NamePlacement.ABOVE ? offset_y_above : offset_y_below);

		playerLabel = new PlayerLabel(labelPosition, HorizontalPositionMode.CENTER,
		    placement == NamePlacement.ABOVE ? VerticalPositionMode.BOTTOM : VerticalPositionMode.TOP,
		    font, renderer);
	}

	void setPlayer(ClientPlayer player)
	{
		this.player = player;
		playerLabel.setPlayer(player);
		player.getGrid().setPosition(position);
	}

	void clearPlayer()
	{
		this.player = null;
		playerLabel.clearPlayer();
	}

	void render(ref Renderer renderer)
	{
		if (player !is null) {
			player.getGrid().render(renderer);
		}

		bool overrideColor = false;

		if (player !is null && player.disconnected)
		{
			playerLabel.nameLabel.setColor(SDL_Color(255, 0, 0, 255));     // red
			overrideColor = true;

			Point labelPos = playerLabel.nameLabel.getPosition();
			int x = labelPos.x - disconnectedIcon.width - 5;
			renderer.renderCopy(disconnectedIcon, x, labelPos.y - 2);
		}
		playerLabel.render(renderer, overrideColor);
	}
}

abstract class ClickableCardPile : Clickable
{
	Point position;

	this(Point position)
	{
		this.position = position;
		this.setRectangle(Rectangle(position.x, position.y, card_large_width, card_large_height));
	}

	void render(ref Renderer renderer, const bool windowHasFocus)
	{
		getShownCard().ifPresent!( c => c.draw(renderer, position, card_large_width, card_large_height,
			windowHasFocus && itemFocusType != FocusType.STRONG && shouldBeHighlighted() ?
			highlightMode() : unhoveredHighlightMode()) );
	}

	mixin MouseUpActivation;

	abstract Nullable!(const Card) getShownCard();
	abstract Card.Highlight highlightMode();
	abstract Card.Highlight unhoveredHighlightMode();
}

abstract class DraggableCardPile : ClickableCardPile
{
	mixin DragAndDrop;

	this(Point position)
	{
		super(position);
	}

	override void render(ref Renderer renderer, const bool windowHasFocus)
	{
		auto drawPosition = position;
		Card.Highlight mode = windowHasFocus && itemFocusType != FocusType.STRONG
				&& shouldBeHighlighted() ? highlightMode() : unhoveredHighlightMode();

		if ( isBeingDragged() || (isDropped() && numberOfAnimations == 0) ) {
			drawPosition = drawPosition.offset( positionAdjustment()[] );

			mode = isBeingDragged() ? Card.Highlight.HOVER : Card.Highlight.OFF;
		}

		getShownCard().ifPresent!( c => c.draw(renderer, drawPosition,
		                                       card_large_width, card_large_height, mode) );
	}
}

final class DiscardPile : DraggableCardPile, DragAndDropTarget, Focusable
{
	mixin BasicFocusable;

	private void delegate() dropHandler;

	this(Point position)
	{
		super(position);
	}

	void onDrop(void delegate() @safe handler) @property pure nothrow @nogc
	{
		this.dropHandler = handler;
	}

	override void render(ref Renderer renderer, const bool windowHasFocus)
	{
		if ( isBeingDragged() ) {
			model.getDiscardSecondCard.ifPresent!(
				c => c.draw(renderer, position, card_large_width, card_large_height, Card.Highlight.OFF) );
		}

		super.render(renderer, windowHasFocus);
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
		if (focusType == FocusType.STRONG)
		{
			if (currentMode == UIMode.DRAWN_CARD_ACTION) {
				return Card.Highlight.PLACE;
			}
			else {
				return Card.Highlight.HAS_FOCUS;
			}
		}
		else if (focusType == FocusType.WEAK)
		{
			return Card.Highlight.HAS_FOCUS_MOUSE_MOVED;
		}

		if (currentMode == UIMode.SWAP_CARD_ACTION) {
			return Card.Highlight.PLACE;
		}
		else {
			return Card.Highlight.OFF;
		}
	}

	override Rectangle[] getBoxes()
	{
		return [box];
	}

	override void drop(Rectangle r)
	{
		dropHandler();
	}

	override Focusable nextUp()
	{
		return this;
	}

	override Focusable nextDown()
	{
		focusType = FocusType.NONE;
		return localPlayer.getGrid;
	}

	override Focusable nextLeft()
	{
		if ( drawPile.focusEnabled() ) {
			focusType = FocusType.NONE;
			return drawPile;
		}
		else {
			return this;
		}
	}

	override Focusable nextRight()
	{
		if ( cancelButton.focusEnabled() ) {
			focusType = FocusType.NONE;
			return cancelButton;
		}
		else {
			return this;
		}
	}

	override Focusable nextTab()
	{
		focusType = FocusType.NONE;
		return localPlayer.getGrid;
	}

	override bool focusEnabled()
	{
		return this.enabled && (currentMode == UIMode.DRAWN_CARD_ACTION || currentMode == UIMode.MY_TURN_ACTION);
	}
}

final class DrawPile : ClickableCardPile, Focusable
{
	mixin BasicFocusable;

	this(Point position)
	{
		super(position);
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
		if (focusType == FocusType.STRONG)
			return Card.Highlight.HAS_FOCUS;
		else if (focusType == FocusType.WEAK)
			return Card.Highlight.HAS_FOCUS_MOUSE_MOVED;
		else
			return Card.Highlight.OFF;
	}

	override Focusable nextUp()
	{
		return this;
	}

	override Focusable nextDown()
	{
		focusType = FocusType.NONE;
		return localPlayer.getGrid;
	}

	override Focusable nextLeft()
	{
		return this;
	}

	override Focusable nextRight()
	{
		if ( discardPile.focusEnabled() ) {
			focusType = FocusType.NONE;
			return discardPile;
		}
		else if ( cancelButton.focusEnabled() ) {
			focusType = FocusType.NONE;
			return cancelButton;
		}
		else {
			return this;
		}
	}

	override Focusable nextTab()
	{
		return nextRight();
	}

	override bool focusEnabled()
	{
		return this.enabled();
	}
}

final class DrawnCard : DraggableCardPile
{
	Card drawnCard;

	this(Point position)
	{
		super(position);
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
	SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "Skyjump - Error", userMessage.toStringz, null);
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
		file.writeln("Skyjump crash report\n---\n", Clock.currTime());
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
