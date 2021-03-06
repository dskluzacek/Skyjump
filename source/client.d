/*
 * client.d
 * 
 * Copyright (c) 2021 David P Skluzacek
 */

module client;
@safe:

import std.stdio : writeln, File;
import std.algorithm : each, filter, count;
import std.string : strip, toStringz;
import std.exception : enforce;
import std.range.primitives;
import std.typecons : Tuple, tuple, Nullable, nullable, Flag, Yes, No;
import std.datetime : Clock;
import std.socket;
import std.conv : to;
import std.container : DList;
import core.time;
import core.thread;
import core.memory;

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
import texturesheet;
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
import theme;

enum window_title = "Skyjump";
enum version_str  = "v0.0.5";

enum ushort port_number = 7684;
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

version (Android) {
    enum name_field_dims = Rectangle(690, 440, 1000, 100);
    enum server_field_dims = Rectangle(690, 555, 1000, 100);

    enum ui_font_size = 52;
    enum medium_font_size = 64;
    enum small_font_size = 48;
    enum tiny_font_size = 36;
    enum name_font_size = 48;
    enum text_field_font_size = 72;

    enum cancel_button_dims = Rectangle(1248, 175, 240, 80);
    enum connect_button_dims = Rectangle(800, 680, 320, 80);
    enum felt_theme_btn_dims = Rectangle(1665, 985, 240, 80);
    enum wood_theme_btn_dims = Rectangle(1410, 985, 240, 80);

    enum opp_grid_x = 88;
    enum opp_grid_y = 15;
    enum opp_grid_rt_x = 1417;
    enum opp_grid_lower_y = 580;
}
else {
    enum name_field_dims = Rectangle(777, 490, 550, 50);
    enum server_field_dims = Rectangle(777, 550, 550, 50);

    enum ui_font_size = 26;
    enum large_font_size = 42;
    enum medium_font_size = 32;
    enum small_font_size = 24;
    enum tiny_font_size = 20;
    enum name_font_size = 37;
    enum text_field_font_size = 36;

    enum cancel_button_dims = Rectangle(1248, 215, 120, 40);
    enum connect_button_dims = Rectangle(880, 620, 160, 40);
    enum felt_theme_btn_dims = Rectangle(1785, 1025, 120, 40);
    enum wood_theme_btn_dims = Rectangle(1655, 1025, 120, 40);

    enum opp_grid_x = 40;
    enum opp_grid_y = 40;
    enum opp_grid_rt_x = 1464;
    enum opp_grid_lower_y = 580;
}

enum icon_gap = 5;

enum disconnected_color = SDL_Color(255, 0, 0, 255);
enum black = SDL_Color(  0,   0,   0, 255),
     white = SDL_Color(255, 255, 255, 255),
     blue  = SDL_Color(  0,   0, 255, 255),
     cyan  = SDL_Color(  0, 255, 255, 255);


enum total_audio_channels        = 8,
     num_reserved_audio_channels = 3;

enum connect_timeout = 12.seconds;

enum sound_effect_delay =   1.seconds;
enum long_anim_duration = 750.msecs;
enum medium_anim_duration = 450.msecs;
enum short_anim_duration      = 285.msecs;
enum dragged_anim_speed = 0.728f;   // pixels per ms
enum fast_anim_speed = 1.456f;   // pixels per ms

private
{
    GameModel model;
    SocketSet socketSet;
    ConnectionToServer connection;
    Font nameFont;
    Font largeFont;
    Font mediumFont;
    Font smallFont;
    Font tinyFont;
    Font uiFont;
    Font textFieldFont;
    TextureRegion disconnectedIcon;
    TextureRegion victoryIcon;
    Texture woodTexture;
    Texture greenFeltTexture;
    Sound dealSound;
    Sound flipSound;
    Sound discardSound;
    Sound drawSound;
    Sound yourTurnSound;
    Sound lastTurnSound;
    version (Android) {} else SDL_Cursor* arrowCursor;
    version (Android) {} else SDL_Cursor* iBeamCursor;
    OpponentGrid[] opponentGrids;
    Background gameBackground;
    DrawPile drawPile;
    DiscardPile discardPile;
    DrawnCard drawnCard;
    Button cancelButton;
    Button connectButton;
    Button woodThemeButton;
    Button greenFeltThemeButton;
    Card opponentDrawnCard;
    Card unknown_card;
    Rectangle opponentDrawnCardRect;
    Label lastTurnLabel1;
    Label lastTurnLabel2;
    Label serverFieldLabel;
    Label nameFieldLabel;
    Label feedbackLabel;
    Label themeLabel;
    Theme activeTheme;
    MoveAnimation moveAnim;
    DealAnimation dealAnim;
    DList!(void delegate()) pendingActions;
    MonoTime yourTurnSoundTimerStart;
    MonoTime lastTurnSoundTimerStart;
    MonoTime connectAttemptTimerStart;
    version (Android) {
        ContextButton pasteButton;
        MonoTime fingerDownTimerStart;
        TextComponent fingerDownWidget;
        Point lastMousePosition;
        Point currentMousePosition;
    }
    TextComponent[] textComponents;
    TextField nameTextField;
    TextField serverTextField;
    Focusable focusedItem;
    FocusType itemFocusType = FocusType.NONE;
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
    WAITING,
    END_GAME
}

version (Android)
{
    pragma(msg, "Compiling Skyjump for Android...");

    import core.runtime : rt_init, rt_term;

    extern (C) int SDL_main() @system
    {
        rt_init();

        scope(exit) rt_term();

        run();
        return 0;
    }
}
else
{
    void main() @system
    {
        try {
            run();
            return;
        }
        catch (Error err) {                          // @suppress(dscanner.suspicious.catch_em_all)
            logFatalException(err, "Runtime error");
            debug writeln('\n', err);
        }
        catch (Throwable ex) {                          // @suppress(dscanner.suspicious.catch_em_all)
            logFatalException(ex, "Uncaught exception");
            debug writeln('\n', ex);
        }

        if ( isSDLLoaded() )
        {
            showErrorDialog("An error occurred and Skyjump is closing.");
        }
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

        version (Android)
        {
            SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "best");
        }
        else version (linux)
        {
            // enable OpenGL multisampling
            SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 1);
            SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 8);

            SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "linear");
        }
        else version (Windows)
        {
            SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "best");
        }
    }
    catch (SDL2Exception e) {
        if ( isSDLLoaded() ) {
            showErrorDialog(e, "SDL could not be initialized", Yes.logToFile);
        }
        else {
            logFatalException(e, "Failed to load the SDL2 shared library");
        }
        return false;
    }

    /* -- Create window and renderer -- */
    try {
        version (Android)
        {
            Rectangle screenRect = Rectangle(0, 0, 320, 240);
            SDL_DisplayMode displayMode;

            if (SDL_GetCurrentDisplayMode(0, &displayMode) == 0)
            {
                screenRect.w = displayMode.w;
                screenRect.h = displayMode.h;
            }

            window = Window( "",
            SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
            screenRect.w, screenRect.h,
            SDL_WINDOW_FULLSCREEN
            | SDL_WINDOW_RESIZABLE );

            renderer = window.createRenderer(cast(SDL_RendererFlags) 0);
            
            if (displayMode.w / cast(float) displayMode.h != 16.0f / 9.0f)
            {
                renderer.setLogicalSize(1920, 1080);
            }
        }
        else
        {
            window = Window( window_title,
            SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
            1200, 675,
            SDL_WINDOW_HIDDEN
            | SDL_WINDOW_RESIZABLE );

            renderer = window.createRenderer( SDL_RENDERER_ACCELERATED
                                              | SDL_RENDERER_PRESENTVSYNC );
        }

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

    unknown_card = new Card(CardRank.UNKNOWN);
    drawPile = new DrawPile(draw_pile_position);
    discardPile = new DiscardPile(discard_pile_position);
    drawnCard = new DrawnCard(drawn_card_position);
    opponentGrids = new OpponentGrid[4];
    socketSet = new SocketSet();

    if ( ! initialize(window, renderer) ) {
        return;
    }
    bool quit = false;

    auto controller = KeyboardController();
    version (Android) {} else { controller.setQuitHandler({ quit = true; }); }

    load(renderer);
    window.visible = true;
    enterMainLoop(window, renderer, quit, controller);
}

void load(ref Renderer renderer)
{
    version (Android) {
        enum assetPath = "";
    }
    else {
        enum assetPath = "assets/";
    }
    uiFont = openFont(assetPath ~ "Metropolis-ExtraBold.ttf", ui_font_size);
    
    version (Android) {
        largeFont = uiFont;
        tinyFont = openFont(assetPath ~ "RobotoCondensed-Regular.ttf", tiny_font_size);
    }
    else {
        largeFont = openFont(assetPath ~ "Metropolis-ExtraBold.ttf", large_font_size);
        tinyFont = openFont(assetPath ~ "Metropolis-SemiBold.ttf", tiny_font_size);
    }
    mediumFont = openFont(assetPath ~ "Metropolis-Medium.ttf", medium_font_size);
    smallFont = openFont(assetPath ~ "Metropolis-Medium.ttf", small_font_size);
    nameFont = openFont(assetPath ~ "Metropolis-SemiBold.ttf", name_font_size);
    textFieldFont = openFont(assetPath ~ "RobotoCondensed-Regular.ttf", text_field_font_size);

    localPlayer = new LocalPlayer();
    localPlayerLabel = new PlayerLabel(Point(1354, 1060), HorizontalPositionMode.LEFT,
                                       VerticalPositionMode.BOTTOM, nameFont, tinyFont, renderer);

    cancelButton = new Button(cancel_button_dims, "Cancel", uiFont, renderer);
    cancelButton.visible = false;

    auto clickableGrid = new ClickablePlayerGrid(Point(586, 320));
    clickableGrid.setFocusables(drawPile, discardPile, cancelButton);
    localPlayer.setGrid(clickableGrid);

    cancelButton.nextTab = clickableGrid;
    cancelButton.nextDown = clickableGrid;

    loadConnectUI(renderer);

    lastTurnLabel1 = new Label("Last", largeFont);
    lastTurnLabel1.setPosition(960, 135, HorizontalPositionMode.CENTER, VerticalPositionMode.BOTTOM);
    lastTurnLabel1.renderText(renderer);
    lastTurnLabel1.setVisible(false);

    lastTurnLabel2 = new Label("Turn!", largeFont);
    lastTurnLabel2.setPosition(960, 135, HorizontalPositionMode.CENTER, VerticalPositionMode.TOP);
    lastTurnLabel2.renderText(renderer);
    lastTurnLabel2.setVisible(false);

    opponentGrids[0] =
        new OpponentGrid(Point(opp_grid_x, opp_grid_lower_y), NamePlacement.ABOVE, nameFont, tinyFont, renderer);
    opponentGrids[1] =
        new OpponentGrid(Point(opp_grid_x, opp_grid_y), NamePlacement.BELOW, nameFont, tinyFont, renderer);
    opponentGrids[2] =
        new OpponentGrid(Point(opp_grid_rt_x, opp_grid_y), NamePlacement.BELOW, nameFont, tinyFont, renderer);
    opponentGrids[3] =
        new OpponentGrid(Point(opp_grid_rt_x, opp_grid_lower_y), NamePlacement.ABOVE, nameFont, tinyFont, renderer);

    woodTexture = renderer.loadTexture(assetPath ~ "wood.png");
    greenFeltTexture = renderer.loadTexture(assetPath ~ "felt.jpg");
    gameBackground = Background(woodTexture);

    woodThemeButton = new Button(wood_theme_btn_dims, "Wood", uiFont, renderer);
    greenFeltThemeButton = new Button(felt_theme_btn_dims, "Green", uiFont, renderer);

    auto woodTheme = Theme(woodTexture, black, blue);
    activeTheme = woodTheme;

    woodThemeButton.enabled = true;
    woodThemeButton.onClick = () @safe { setTheme(woodTheme, renderer); };

    greenFeltThemeButton.enabled = true;
    greenFeltThemeButton.onClick = delegate() @safe
      { setTheme(Theme(greenFeltTexture, white, cyan), renderer); };

    themeLabel = new Label("Theme: ", mediumFont);
    themeLabel.setPosition(wood_theme_btn_dims.x, wood_theme_btn_dims.y + wood_theme_btn_dims.h / 2,
                           HorizontalPositionMode.RIGHT, VerticalPositionMode.CENTER);
    themeLabel.renderText(renderer);

    loadCardsAndSounds(renderer, assetPath);
}

void loadConnectUI(ref Renderer renderer)
{
    enum text_field_padding =  4,
         server_addr_max    = 20;
    
    version (Android) {
        enum arrowCursor = null;
        enum iBeamCursor = null;
    } else {
        arrowCursor = createCursor(SDL_SYSTEM_CURSOR_ARROW);
        iBeamCursor = createCursor(SDL_SYSTEM_CURSOR_IBEAM);
    }

    nameTextField = new TextField(textFieldFont, name_field_dims, text_field_padding, arrowCursor, iBeamCursor);
    nameTextField.maxTextLength = MAX_NAME_LENGTH;
    serverTextField = new TextField(textFieldFont, server_field_dims, text_field_padding, arrowCursor, iBeamCursor);
    serverTextField.maxTextLength = server_addr_max;
    debug serverTextField.setText("localhost", renderer);
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

    version (Android) {
        addTextFieldObservers(nameFieldLabel, nameTextField, name_field_dims, serverTextField, serverFieldLabel);
        addTextFieldObservers(serverFieldLabel, serverTextField, server_field_dims, nameTextField, nameFieldLabel);
    
        pasteButton = new ContextButton("Paste", cancel_button_dims.h * 3/2, uiFont, renderer);
    }
}

void loadCardsAndSounds(ref Renderer renderer, string assetPath)
{
    Texture sheetTexture = renderer.loadTexture(assetPath ~ "sheet.png");
    TextureSheet sheet = loadTextureSheet(assetPath ~ "sheet", sheetTexture);
    
    Card.setTexture(CardRank.NEGATIVE_TWO, sheet["-2"]);
    Card.setTexture(CardRank.NEGATIVE_ONE, sheet["-1"]);
    Card.setTexture(CardRank.ZERO, sheet["0"]);
    Card.setTexture(CardRank.ONE, sheet["1"]);
    Card.setTexture(CardRank.TWO, sheet["2"]);
    Card.setTexture(CardRank.THREE, sheet["3"]);
    Card.setTexture(CardRank.FOUR, sheet["4"]);
    Card.setTexture(CardRank.FIVE, sheet["5"]);
    Card.setTexture(CardRank.SIX, sheet["6"]);
    Card.setTexture(CardRank.SEVEN, sheet["7"]);
    Card.setTexture(CardRank.EIGHT, sheet["8"]);
    Card.setTexture(CardRank.NINE, sheet["9"]);
    Card.setTexture(CardRank.TEN, sheet["10"]);
    Card.setTexture(CardRank.ELEVEN, sheet["11"]);
    Card.setTexture(CardRank.TWELVE, sheet["12"]);
    Card.setTexture(CardRank.UNKNOWN, sheet["back"]);

    Card.setShadowTexture(sheet["shadow"]);
    Card.setStackShadowTexture(sheet["shadow2"]);
    Button.setCornerTexture(sheet["corner"]);

    disconnectedIcon = sheet["network-x"];
    victoryIcon = sheet["star"];

    version (Windows) {
        enum soundExtension = ".wav";
    }
    else {
        enum soundExtension = ".ogg";
    }
    dealSound = loadWAV(assetPath ~ "playcard" ~ soundExtension);
    flipSound = loadWAV(assetPath ~ "cardPlace3" ~ soundExtension);
    discardSound = loadWAV(assetPath ~ "cardShove1" ~ soundExtension);
    drawSound = loadWAV(assetPath ~ "draw" ~ soundExtension);
    yourTurnSound = loadWAV(assetPath ~ "cuckoo" ~ soundExtension);
    lastTurnSound = loadWAV(assetPath ~ "UI_007" ~ soundExtension);
}

version (Android)
{
    void addTextFieldObservers(Label label, TextField textField, Rectangle fieldDimensions,
                               TextField otherTextField, Label otherLabel)
    {
        Point usualPosition = label.getPosition();
        
        textField.addObserver!"textInputStarted"({
            label.setPosition(name_field_dims.x, y_position_receiving_input + fieldDimensions.h / 2,
                              HorizontalPositionMode.RIGHT, VerticalPositionMode.CENTER);
            otherTextField.enabled = false;
            otherTextField.visible = false;
            otherLabel.setVisible(false);
        });

        textField.addObserver!"textInputEnded"({
            label.setPosition(usualPosition.x, usualPosition.y);
            otherTextField.enabled = true;
            otherTextField.visible = true;
            otherLabel.setVisible(true);
        });
    }
}
else
{
    SDL_Cursor* createCursor(SDL_SystemCursor c) @trusted nothrow @nogc
    {
        return SDL_CreateSystemCursor(c);
    }
}

void setTheme(Theme theme, ref Renderer renderer)
{
    activeTheme = theme;
    gameBackground.setTexture(theme.getBackgroundTexture);
    theme.updateLabelColors(
        [lastTurnLabel1, lastTurnLabel2, serverFieldLabel, nameFieldLabel, feedbackLabel, themeLabel]);
    lastTurnLabel1.renderText(renderer);
    lastTurnLabel2.renderText(renderer);
    serverFieldLabel.renderText(renderer);
    nameFieldLabel.renderText(renderer);
    themeLabel.renderText(renderer);
}

void enterMainLoop(ref Window window,
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
    addClickable(woodThemeButton);
    addClickable(greenFeltThemeButton);
    addClickable(drawnCard);
    addClickable(nameTextField);
    addClickable(serverTextField);
    version (Android) { addClickable(pasteButton); }

    // SDL_Log( ("gl swap interval= " ~ SDL_GL_GetSwapInterval().to!string).toStringz );

    mainLoop(window, renderer, quit, controller);
}

void mainLoop(ref Window window,
              ref Renderer renderer,
              ref bool quit,
              ref KeyboardController controller)
{
    MonoTime currentTime;
    MonoTime lastTime = MonoTime.currTime();

    () @trusted { 
        GC.collect();
        GC.disable();
    }();

    while (! quit)
    {
        version (Android) {
        }
        else
        {
            static bool firstFrame = true;
            
            currentTime = MonoTime.currTime();
            auto elapsed = currentTime - lastTime;

            enum microseconds = 16_600;  // limits the framerate to ~60 fps

            if ( elapsed < dur!"usecs"(microseconds) )
            {
                sleepFor( dur!"usecs"(microseconds) - elapsed);
            }
            currentTime = MonoTime.currTime();
            elapsed = currentTime - lastTime;
            lastTime = currentTime;
        }

        bool somethingChanged = pollServer();
        somethingChanged = pollInputEvents(quit, controller, renderer) || somethingChanged;

        playSoundsOnTimers();

        if (currentMode == UIMode.DEALING)
        {
            if ( dealAnim.process() ) {
                connection.send(ClientMessageType.READY);  // let the server know animation finished
                currentMode = UIMode.NO_ACTION;
            }
        }
        else
        {
            version (Android) {} else version (Windows) {} else {
                if (numberOfAnimations == 0 && !(somethingChanged || firstFrame)) {
                    renderer.present();
                    continue;
                }
            }
        }

        if ( moveAnim.process() )  // true if moveAnim finished
        {
            static bool gcRun = true;
            static bool gcCollectNext;  // flag used to skip every other possible GC.collect()

            if (numberOfAnimations > 0) {
                --numberOfAnimations;
                gcRun = false;
                gcCollectNext = ! gcCollectNext;
            }

            while (numberOfAnimations == 0 && ! pendingActions.empty) {
                ( pendingActions.front() )();
                pendingActions.removeFront();
            }

            bool localPlayerTurn = false;
            auto playerCurrTurn = model.playerWhoseTurnItIs();
            playerCurrTurn.ifPresent!( p => localPlayerTurn = p is localPlayer );

            if (numberOfAnimations == 0 && pendingActions.empty 
                && gcCollectNext && gcRun == false && localPlayerTurn == false)
            {
                () @trusted { GC.collect(); } ();
                gcRun = true;
            }
        }
        version (Android) {} else { firstFrame = false; }

        render(window, renderer);
    }
}

void render(ref Window window, ref Renderer renderer)
{
    renderer.setDrawColor(0, 0, 0, 255);
    renderer.clear();
    version (Android) {} else { renderer.setLogicalSize(0, 0); }
    gameBackground.render(renderer, window);
    version (Android) {} else { renderer.setLogicalSize(1920, 1080); }

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
    themeLabel.draw(renderer);

    nameTextField.draw(renderer);
    serverTextField.draw(renderer);

    woodThemeButton.draw(renderer);
    greenFeltThemeButton.draw(renderer);

    drawPile.render(renderer, windowHasFocus);
    discardPile.render(renderer, windowHasFocus);
    drawnCard.render(renderer, windowHasFocus);

    renderOppDrawnCard(renderer);
    moveAnim.render(renderer);

    if (currentMode == UIMode.DEALING) {
        dealAnim.render(renderer);
    }
    
    version (Android) { pasteButton.draw(renderer); }

    renderer.present();
}

void renderOppDrawnCard(ref Renderer renderer)
{
    if (opponentDrawnCard !is null)
    {
        opponentDrawnCard.draw(renderer, opponentDrawnCardRect, Card.Highlight.OFF, Card.Shadow.ON);
    }
}

void playSoundsOnTimers()
{
    if (lastTurnSoundTimerStart != MonoTime.init
        && MonoTime.currTime() - lastTurnSoundTimerStart > sound_effect_delay)
    {
        lastTurnSound.play();
        lastTurnSoundTimerStart = MonoTime.init;

        if (yourTurnSoundTimerStart != MonoTime.init) {
            yourTurnSoundTimerStart = MonoTime.currTime();
        }
    }

    if (yourTurnSoundTimerStart != MonoTime.init
        && MonoTime.currTime() - yourTurnSoundTimerStart > sound_effect_delay)
    {
        yourTurnSound.play();
        yourTurnSoundTimerStart = MonoTime.init;
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
    localPlayer.reset();
    localPlayer.setName(name);

    Socket socket;

    try {
        auto addr = new InternetAddress(address, port_number);
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

/**
 * Check for messages from the server. $(BR)
 * Returns true if message recieved or connection state changed.
 */
bool pollServer()
{
    if (connection is null) {
        return false;
    }
    socketSet.reset();
    socketSet.add(connection.socket);
    bool result;

    if (connection.isConnected)
    {
        Nullable!ServerMessage message;

        try {
            Socket.select(socketSet, null, null, 100.usecs);
            message = connection.poll(socketSet);

            message.ifPresent!((message) {
                result = true;

                if (currentMode == UIMode.CONNECT) {
                    leaveConnectMode();
                }
                bool stop = handleMessage(message);

                if (stop) {
                    resetConnection();
                }
            });
        }
        catch (JoinException e) {
            feedbackLabel.setText(connect_failed_str);
            resetConnection();
            return true;
        }
        catch (SocketReadException e) {
            feedbackLabel.setText("The connection to the server was lost.");
            resetConnection();
            return true;
        }
    }
    else
    {
        tryToJoin();
    }
    assert(connectAttemptTimerStart != MonoTime.init);

    return processConnectTimer() || result;
}

void tryToJoin()
{
    Socket.select(null, socketSet, null, 100.usecs);
    connection.checkConnected(socketSet);

    if (connection.isConnected)
    {
        connection.send(ClientMessageType.JOIN, localPlayer.getName);
        return;
    }
}

bool processConnectTimer()
{
    if (connection !is null && ! connection.isDataReceived
        && MonoTime.currTime() - connectAttemptTimerStart > connect_timeout)
    {
        feedbackLabel.setText(connect_failed_str);
        resetConnection();
        return true;
    }
    return false;
}

/**
 * Processes input events from the SDL event queue. $(BR)
 * Returns true if an event that we care about occured.
 */
bool pollInputEvents(ref bool quit, ref KeyboardController controller, ref Renderer renderer)
{
    @trusted auto poll(ref SDL_Event ev)
    {
        return SDL_PollEvent(&ev);
    }

    @trusted auto getModState()
    {
        return SDL_GetModState();
    }

    SDL_Event e;
    bool result = false;
    auto textWidget = textComponents.filter!(a => a.acceptingTextInput);

    while ( poll(e) )
    {
        // If user closes the window:
        if (e.type == SDL_QUIT)
        {
            quit = true;
            return true;
        }
        else if (e.type == SDL_TEXTINPUT)
        {
            if (! textWidget.empty)
            {
                textWidget.front.inputEvent(e.text, renderer);
                result = true;
            }
        }
        else if (e.type == SDL_KEYDOWN)
        {
            // e.key is SDL_KeyboardEvent field in SDL_Event
            
            if ( ! textWidget.empty )
            {
                if (e.key.keysym.scancode == SDL_SCANCODE_V && getModState() & KMOD_CTRL)
                {
                    SDLClipboardText text = SDLClipboardText.getClipboardText();

                    if (text.hasText) {
                        textWidget.front.paste(text.get, renderer);
                        result = true;
                    }
                }
                else if ( textWidget.front.keyboardEvent(e.key, renderer) )
                {
                    result = true;
                    continue;
                }
            }
               
            if ((e.key.keysym.scancode == SDL_SCANCODE_LEFT || e.key.keysym.scancode == SDL_SCANCODE_RIGHT
                || e.key.keysym.scancode == SDL_SCANCODE_UP || e.key.keysym.scancode == SDL_SCANCODE_DOWN
                || e.key.keysym.sym == SDLK_TAB) && ! e.key.repeat)
            {
                focusKeyPress(e.key.keysym.scancode);
                result = true;
            }
            else if ((e.key.keysym.scancode == SDL_SCANCODE_SPACE || e.key.keysym.scancode == SDL_SCANCODE_RETURN
                     || e.key.keysym.scancode == SDL_SCANCODE_KP_ENTER) && ! e.key.repeat)
            {
                focusActivate();
                result = true;
            }
            else
            {
                version (Android) {} else {
                    controller.handleEvent(e.key);
                    result = true;
                }
            }
        }
        else if (e.type == SDL_MOUSEMOTION)
        {
            result = true;
            
            version (Android) {
                currentMousePosition.x = e.button.x;
                currentMousePosition.y = e.button.y;
            }

            focusMouseMoved();
            notifyObservers!"mouseMotion"(e.motion);
        }
        else if (e.type == SDL_MOUSEBUTTONDOWN)
        {
            result = true;
            
            version (Android) {
                fingerDownTimerStart = MonoTime.currTime();
                lastMousePosition.x = e.button.x;
                lastMousePosition.y = e.button.y;
                currentMousePosition = lastMousePosition;

                if ( pasteButton.acceptsClick(Point(e.button.x, e.button.y)) )
                {
                    pasteButton.mouseButtonDown( Point(e.button.x, e.button.y) );
                    continue;
                }
            }
 
            if (moveAnim.isFinished && e.button.button == SDL_BUTTON_LEFT) {
                notifyObservers!"mouseDown"(e.button);
            }
        }
        else if (e.type == SDL_MOUSEBUTTONUP )
        {
            version (Android) { fingerDownTimerStart = MonoTime.init; }

            if (moveAnim.isFinished && e.button.button == SDL_BUTTON_LEFT) {
                notifyObservers!"mouseUp"(e.button);
            }
            result = true;
        }
    }

    version (Android) {
        return checkForLongPress(textWidget, renderer) || result;
    }
    else {
        return result;
    }
}

bool checkForLongPress(T)(T textWidgetRange, ref Renderer renderer)
{
    if (! textWidgetRange.empty && fingerDownTimerStart != MonoTime.init
        && MonoTime.currTime() - fingerDownTimerStart > 800.msecs)
    {
        auto widget = textWidgetRange.front;
        
        if (distance(lastMousePosition, currentMousePosition) <= 100)
        {
            fingerDownTimerStart = MonoTime.init;
            
            pasteButton.onClick = {
                SDLClipboardText text = SDLClipboardText.getClipboardText();
                if (text.hasText) { widget.paste(text.get, renderer); }
                pasteButton.onClick = {};
            };
            pasteButton.show(currentMousePosition);
            return true;
        }
    }
    return false;
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
    woodThemeButton.windowFocusNotify(type);
    greenFeltThemeButton.windowFocusNotify(type);
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
        pendingActions.insertBack({
            model.getPlayer(message.playerNumber.to!ubyte).setWinner(true);
            currentMode = UIMode.END_GAME;
        });
        break;
    case ServerMessageType.YOUR_TURN:
        pendingActions.insertBack( delegate() {
            model.setPlayerCurrentTurn(localPlayerNumber);
            beginOurTurn();
        });
        break;
    case ServerMessageType.RESUME_DRAW:
        pendingActions.insertBack( delegate() {
            enforce!ProtocolException(drawnCard.drawnCard !is null);
            enterDrawnCardActionMode();
            yourTurnSoundTimerStart = MonoTime.currTime();
        });
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
        newGame();
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
    themeLabel.setVisible(false);
    woodThemeButton.visible = false;
    greenFeltThemeButton.visible = false;
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
    themeLabel.setVisible(true);
    woodThemeButton.visible = true;
    woodThemeButton.enabled = true;
    greenFeltThemeButton.visible = true;
    greenFeltThemeButton.enabled = true;

    model.reset();

    localPlayer.getGrid.clear();
    localPlayerLabel.clearPlayer();
    opponentGrids.each!( g => g.clearPlayer() );
    opponentDrawnCard = null;
    drawnCard.drawnCard = null;
    updateOppGridsEnabledStatus(0);
}

void newGame()
{
    enterNoActionMode(UIMode.PRE_GAME);

    moveAnim.cancel();
    pendingActions.clear();

    model.newGame();
    opponentDrawnCard = null;
    drawnCard.drawnCard = null;
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
    ubyte n = number.to!ubyte;
    
    if ( model.hasPlayer(n) ) {
        model[n].setName(name);
    }
    else {
        ClientPlayer p = new ClientPlayer(name);
        p.setGrid( new ClientPlayerGrid!() );
        model.setPlayer(p, n);

        updateOppGridsEnabledStatus(model.numberOfPlayers);
        assignOpponentPositions();
    }
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

    if (currentMode != UIMode.DEALING) {
        enterNoActionMode(UIMode.WAITING);
    }

    (cast(ClientPlayer) model.getPlayer(number.to!ubyte)).disconnected = true;
}

void playerReconnected(int number)
{
    (cast(ClientPlayer) model.getPlayer(number.to!ubyte)).disconnected = false;
}

void beginDealing(int dealer)
{
    if (model.getPlayerOut.isNotNull)
    {
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

    dealAnim = new DealAnimation(draw_pile_position, clientGrids, short_anim_duration,
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
    Duration minDuration;
    float animSpeed;

    if ( discardPile.isDropped() ) {
        originRect = discard_pile_rect.offset( discardPile.positionAdjustment()[] );
        animSpeed = dragged_anim_speed;
        minDuration = 0.seconds;
    }
    else {
        originRect = discard_pile_rect;
        animSpeed = fast_anim_speed;
        minDuration = medium_anim_duration;
    }

    moveAnim = MoveAnimation(popped.get, originRect, cardRect, animSpeed, minDuration);
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

        moveAnim = MoveAnimation(c, cardRect, discard_pile_rect, fast_anim_speed, medium_anim_duration);
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

    auto placeHandler = delegate(int r, int c) {
        enterNoActionMode();
        connection.send(ClientMessageType.PLACE, r, c);
    };
    localPlayer.getGrid.onClick = placeHandler;
    localPlayer.getGrid.onDrop = placeHandler;

    auto discardHandler = delegate() {
        enterNoActionMode();
        connection.send(ClientMessageType.REJECT);
        discardDrawnCard();
    };
    discardPile.onClick = discardHandler;
    discardPile.onDrop = discardHandler;
}

void showDrawnCard(CardRank rank)
{
    enterNoActionMode();
    drawSound.play();
    Card c = new Card(rank);
    c.revealed = true;

    moveAnim = MoveAnimation(c, draw_pile_rect, drawn_card_rect, short_anim_duration);
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
    Duration minDuration;
    float animSpeed;

    static if (is(T == LocalPlayer)) {
        assignTaken(drawnCard.drawnCard, taken);
        taken.revealed = true;

        if ( drawnCard.isDropped() ) {
            originRect = drawn_card_rect.offset( drawnCard.positionAdjustment()[] );
            animSpeed = dragged_anim_speed;
            minDuration = 0.seconds;
        }
        else {
            originRect = drawn_card_rect;
            animSpeed = fast_anim_speed;
            minDuration = medium_anim_duration;
        }
        moveAnim = MoveAnimation(taken, originRect, cardRect, animSpeed, minDuration);
    }
    else {
        assignTaken(opponentDrawnCard, taken);
        originRect = opponentDrawnCardRect;
        moveAnim = MoveAnimation(taken, originRect, cardRect, long_anim_duration);
    }
    
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

        moveAnim = MoveAnimation(c, cardRect, discard_pile_rect, fast_anim_speed, medium_anim_duration);
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
    float animSpeed;

    if ( drawnCard.isDropped() ) {
        originRect = drawn_card_rect.offset( drawnCard.positionAdjustment()[] );
        animSpeed = dragged_anim_speed;
    }
    else {
        originRect = drawn_card_rect;
        animSpeed = fast_anim_speed;
    }

    moveAnim = MoveAnimation(c, originRect, discard_pile_rect, animSpeed);
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

    moveAnim = MoveAnimation(c, start, discard_pile_rect, fast_anim_speed);
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

    moveAnim = MoveAnimation(unknown_card, draw_pile_rect, dest, fast_anim_speed);
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
    moveAnim = MoveAnimation(a.get, grid.getCardDestination(0, columnIndex), discard_pile_rect, long_anim_duration);
    moveAnim.onFinished = {
        dealSound.play();
        model.pushToDiscard(a.get);
        player[1, columnIndex] = null;

        moveAnim = MoveAnimation(b.get,
            grid.getCardDestination(1, columnIndex), discard_pile_rect, long_anim_duration);
        moveAnim.onFinished = {
            dealSound.play();
            model.pushToDiscard(b.get);
            player[2, columnIndex] = null;

            moveAnim = MoveAnimation(c.get,
                grid.getCardDestination(2, columnIndex), discard_pile_rect, long_anim_duration);
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
    if (model.getPlayerOut.isNotNull) {
        displayScores(scores);
    }

    foreach (key, value; scores)
    {
        model.getPlayer(key).setScore(value);
    }
}

void displayScores(int[ubyte] scores)
{
    foreach (key, value; scores)
    {
        Player p = model.getPlayer(key);
        p.setHandScore((value - p.getScore).nullable);
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
    enum max_text_width = 470;
    
    Player player;
    Label nameLabel;
    Font primaryFont;
    Font smallFont;

    this(Point position, HorizontalPositionMode hMode,
         VerticalPositionMode vMode, Font font, Font smallFont, ref Renderer renderer)
    {
        this.primaryFont = font;
        this.smallFont = smallFont;
        
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
        @trusted void setLabelText(string txt)
        {
            int w;
            TTF_SizeUTF8(primaryFont, txt.toStringz, &w, null);
            
            if (w > max_text_width) {
                nameLabel.setFont(smallFont, false);
            }
            else {
                nameLabel.setFont(primaryFont, false);
            }
            nameLabel.setText(txt);
        }
        
        if (player is null) {
            return;
        }

        if (currentMode == UIMode.PRE_GAME) {
            setLabelText(player.getName);
        }
        else {
            string handScore = "";

            if (player.getHandScore.isNotNull) {
                auto number = player.getHandScore.get;
                handScore = '[' ~ (number >= 0 ? "+" : "") ~ number.to!string ~ ']';
            }

            setLabelText(player.getName ~ ' ' ~ handScore ~ '(' ~ player.getScore.to!string ~ ')');
        }

        if (player.isWinner) {
            Point labelPos = nameLabel.getPosition();
            renderer.renderCopyTR(victoryIcon, labelPos.x + nameLabel.getWidth + icon_gap, labelPos.y - 8);
        }
        auto playerTurn = model.playerWhoseTurnItIs();

        if (overrideColor) {
            // do nothing
        }
        else if (playerTurn.isNotNull && player is playerTurn.get && currentMode != UIMode.PRE_GAME
            && currentMode != UIMode.DEALING && currentMode != UIMode.FLIP_ACTION && currentMode != UIMode.END_GAME)
        {
            nameLabel.setColor(activeTheme.getPlayerTurnTextColor);           // "blue"
        }
        else {
            nameLabel.setColor(activeTheme.getPrimaryTextColor);             // "black"
        }
        nameLabel.draw(renderer);
    }
}

final class OpponentGrid
{
    enum offset_x = 205;

    version (Android) {
        enum offset_y_above = -14,
             offset_y_below = 422;
    }
    else {
        enum offset_y_above = -10,
             offset_y_below = 418;
    }

    private
    {
        Point position;
        ClientPlayer player;
        PlayerLabel playerLabel;
        bool enabled;
    }

    this(Point position, NamePlacement placement, Font font, Font smallFont, ref Renderer renderer)
    {
        this.position = position;

        Point labelPosition
            = position.offset(offset_x, placement == NamePlacement.ABOVE ? offset_y_above : offset_y_below);

        playerLabel = new PlayerLabel(labelPosition, HorizontalPositionMode.CENTER,
            placement == NamePlacement.ABOVE ? VerticalPositionMode.BOTTOM : VerticalPositionMode.TOP,
            font, smallFont, renderer);
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
            playerLabel.nameLabel.setColor(disconnected_color);     // "red"
            overrideColor = true;

            Point labelPos = playerLabel.nameLabel.getPosition();
            int x = labelPos.x - disconnectedIcon.width - icon_gap;
            renderer.renderCopyTR(disconnectedIcon, x, labelPos.y - 5);
        }

        playerLabel.render(renderer, overrideColor);
    }
}

interface InteractiveComponent
{
    bool shouldBeHighlighted();
}

abstract class ClickableCardPile : Clickable, InteractiveComponent
{
    Point position;

    this(Point position)
    {
        this.position = position;
    }

    void render(ref Renderer renderer, const bool windowHasFocus)
    {
        getShownCard().ifPresent!( c => c.draw(renderer, position, card_large_width, card_large_height,
            windowHasFocus && itemFocusType != FocusType.STRONG && shouldBeHighlighted() ?
            highlightMode() : unhoveredHighlightMode(), shadowMode()) );
    }

    abstract Nullable!(const Card) getShownCard();
    abstract Card.Highlight highlightMode();
    abstract Card.Highlight unhoveredHighlightMode();
    abstract Card.Shadow shadowMode();
}

abstract class MouseUpCardPile : ClickableCardPile
{
    mixin MouseUpActivation;

    this(Point position)
    {
        super(position);
        this.setRectangle(Rectangle(position.x, position.y, card_large_width, card_large_height));
    }
}

abstract class MouseDownCardPile : ClickableCardPile
{
    mixin MouseDownActivation;

    this(Point position)
    {
        super(position);
        this.setRectangle(Rectangle(position.x, position.y, card_large_width, card_large_height));
    }
}

abstract class DraggableCardPile : MouseUpCardPile
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
        auto shadow = shadowMode();

        if ( isBeingDragged() || (isDropped() && numberOfAnimations == 0) ) {
            drawPosition = drawPosition.offset( positionAdjustment()[] );

            mode = isBeingDragged() ? Card.Highlight.HOVER : Card.Highlight.OFF;
            shadow = Card.Shadow.OFF;
        }

        getShownCard().ifPresent!( c => c.draw(renderer, drawPosition,
                                               card_large_width, card_large_height, mode, shadow) );
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
            model.getDiscardSecondCard.ifPresent!( c => c.draw(renderer,
                position, card_large_width, card_large_height, Card.Highlight.OFF, shadowMode()) );
        }

        super.render(renderer, windowHasFocus);
    }

    override Nullable!(const Card) getShownCard()
    {
        return model.getDiscardTopCard();
    }

    override Card.Shadow shadowMode()
    {
        if (model.getDiscardPileSize >= 4) {
            return Card.Shadow.STACK;
        }
        else if (model.getDiscardPileSize > 0) {
            return Card.Shadow.ON;
        }
        else {
            return Card.Shadow.OFF;
        }
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

    override bool focusEnabled() const
    {
        return this.enabled && (currentMode == UIMode.DRAWN_CARD_ACTION || currentMode == UIMode.MY_TURN_ACTION);
    }
}

version (Android) {
    alias DrawPileType = MouseDownCardPile;
}
else {
    alias DrawPileType = MouseUpCardPile;
}

final class DrawPile : DrawPileType, Focusable
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

    version (Android)
    {
        override void render(ref Renderer renderer, const bool windowHasFocus)
        {
            if ( !(nameTextField.acceptingTextInput || serverTextField.acceptingTextInput) ) {
                super.render(renderer, windowHasFocus);
            }
        }
    }

    override Card.Shadow shadowMode()
    {
        return Card.Shadow.STACK;
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

    override bool focusEnabled() const
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

    override Card.Shadow shadowMode()
    {
        return Card.Shadow.OFF;
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
        debug writeln(userMessage, "\n(", exc.msg, ")");
    }
    catch (Exception e)
    {
    }
}
