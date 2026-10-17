unit sdl3min;

{ Minimal hand-written SDL3 binding: only what the material flow simulator needs.
  Links against SDL3.dll (SDL 3.2+). }

{$mode objfpc}{$H+}
{$packrecords C}

interface

const
  SDL3LIB = 'SDL3.dll';

  SDL_INIT_VIDEO = $00000020;
  SDL_WINDOW_RESIZABLE = $0000000000000020;

  SDL_EVENT_QUIT = $100;
  SDL_EVENT_KEY_DOWN = $300;
  SDL_EVENT_KEY_UP = $301;
  SDL_EVENT_TEXT_INPUT = $303;
  SDL_EVENT_MOUSE_MOTION = $400;
  SDL_EVENT_MOUSE_BUTTON_DOWN = $401;
  SDL_EVENT_MOUSE_BUTTON_UP = $402;
  SDL_EVENT_MOUSE_WHEEL = $403;

  SDL_BUTTON_LEFT = 1;
  SDL_BUTTON_MIDDLE = 2;
  SDL_BUTTON_RIGHT = 3;

  SDL_BLENDMODE_BLEND = $00000001;
  SDL_LOGICAL_PRESENTATION_LETTERBOX = 2;
  SDL_MESSAGEBOX_ERROR = $00000010;

  SDLK_BACKSPACE = $08;
  SDLK_ESCAPE = $1B;
  SDLK_SPACE = $20;
  SDLK_MINUS = $2D;
  SDLK_EQUALS = $3D;
  SDLK_LEFTBRACKET = $5B;
  SDLK_RIGHTBRACKET = $5D;
  SDLK_DELETE = $7F;
  SDLK_RETURN = $0D;
  SDLK_KP_ENTER = $40000058;
  SDLK_F1 = $4000003A;
  SDLK_F5 = $4000003E;
  SDLK_RIGHT = $4000004F;
  SDLK_LEFT = $40000050;
  SDLK_DOWN = $40000051;
  SDLK_UP = $40000052;
  SDLK_0 = $30;
  SDLK_KP_PLUS = $40000057;
  SDLK_KP_MINUS = $40000056;
  SDLK_F2 = $4000003B;
  SDLK_F3 = $4000003C;
  SDLK_F4 = $4000003D;
  SDLK_F6 = $4000003F;
  SDLK_F7 = $40000040;
  SDLK_F8 = $40000041;
  SDLK_F9 = $40000042;
  SDLK_PAGEUP = $4000004B;
  SDLK_PAGEDOWN = $4000004E;

  SDL_KMOD_SHIFT = $0003;
  SDL_KMOD_CTRL = $00C0;

type
  PSDL_Window = Pointer;
  PSDL_Renderer = Pointer;
  PSDL_Surface = Pointer;
  PSDL_Texture = Pointer;

  TSDL_FPoint = record
    x, y: Single;
  end;

  TSDL_FColor = record
    r, g, b, a: Single;
  end;

  PSDL_FRect = ^TSDL_FRect;
  TSDL_FRect = record
    x, y, w, h: Single;
  end;

  PSDL_Rect = ^TSDL_Rect;
  TSDL_Rect = record
    x, y, w, h: LongInt;
  end;

  PSDL_Vertex = ^TSDL_Vertex;
  TSDL_Vertex = record
    position: TSDL_FPoint;
    color: TSDL_FColor;
    tex_coord: TSDL_FPoint;
  end;

  TSDL_KeyboardEvent = record
    type_: UInt32;
    reserved: UInt32;
    timestamp: UInt64;
    windowID: UInt32;
    which: UInt32;
    scancode: UInt32;
    key: UInt32;
    mod_: UInt16;
    raw: UInt16;
    down: Boolean;
    repeat_: Boolean;
  end;

  TSDL_MouseMotionEvent = record
    type_: UInt32;
    reserved: UInt32;
    timestamp: UInt64;
    windowID: UInt32;
    which: UInt32;
    state: UInt32;
    x, y, xrel, yrel: Single;
  end;

  TSDL_MouseButtonEvent = record
    type_: UInt32;
    reserved: UInt32;
    timestamp: UInt64;
    windowID: UInt32;
    which: UInt32;
    button: UInt8;
    down: Boolean;
    clicks: UInt8;
    padding: UInt8;
    x, y: Single;
  end;

  TSDL_MouseWheelEvent = record
    type_: UInt32;
    reserved: UInt32;
    timestamp: UInt64;
    windowID: UInt32;
    which: UInt32;
    x, y: Single;
    direction: UInt32;
    mouse_x, mouse_y: Single;
  end;

  PSDL_DialogFileFilter = ^TSDL_DialogFileFilter;
  TSDL_DialogFileFilter = record
    name: PAnsiChar;
    pattern: PAnsiChar;
  end;

  { filelist: nil on error, filelist^ = nil when cancelled. May run on another thread. }
  TSDL_DialogFileCallback = procedure(userdata: Pointer; filelist: PPAnsiChar; filter: LongInt); cdecl;

  TSDL_TextInputEvent = record
    type_: UInt32;
    reserved: UInt32;
    timestamp: UInt64;
    windowID: UInt32;
    text: PAnsiChar;      { UTF-8 }
  end;

  PSDL_Event = ^TSDL_Event;
  TSDL_Event = record
    case Integer of
      0: (type_: UInt32);
      6: (text: TSDL_TextInputEvent);
      1: (key: TSDL_KeyboardEvent);
      2: (motion: TSDL_MouseMotionEvent);
      3: (button: TSDL_MouseButtonEvent);
      4: (wheel: TSDL_MouseWheelEvent);
      5: (padding: array[0..127] of Byte);
  end;

function SDL_Init(flags: UInt32): Boolean; cdecl; external SDL3LIB;
procedure SDL_Quit; cdecl; external SDL3LIB;
function SDL_GetError: PAnsiChar; cdecl; external SDL3LIB;
function SDL_ShowSimpleMessageBox(flags: UInt32; title, message: PAnsiChar; window: PSDL_Window): Boolean; cdecl; external SDL3LIB;

function SDL_GetPrimaryDisplay: UInt32; cdecl; external SDL3LIB;
function SDL_GetDisplayUsableBounds(displayID: UInt32; rect: PSDL_Rect): Boolean; cdecl; external SDL3LIB;

function SDL_CreateWindow(title: PAnsiChar; w, h: LongInt; flags: UInt64): PSDL_Window; cdecl; external SDL3LIB;
procedure SDL_DestroyWindow(window: PSDL_Window); cdecl; external SDL3LIB;
function SDL_SetWindowTitle(window: PSDL_Window; title: PAnsiChar): Boolean; cdecl; external SDL3LIB;
function SDL_GetWindowSize(window: PSDL_Window; w, h: PLongInt): Boolean; cdecl; external SDL3LIB;
function SDL_SetWindowSize(window: PSDL_Window; w, h: LongInt): Boolean; cdecl; external SDL3LIB;
function SDL_GetModState: UInt16; cdecl; external SDL3LIB;
{ returns the held buttons: bit 0 left, bit 2 right }
function SDL_GetMouseState(x, y: PSingle): UInt32; cdecl; external SDL3LIB;

procedure SDL_ShowOpenFileDialog(callback: TSDL_DialogFileCallback; userdata: Pointer; window: PSDL_Window;
  filters: PSDL_DialogFileFilter; nfilters: LongInt; default_location: PAnsiChar; allow_many: Boolean); cdecl; external SDL3LIB;
procedure SDL_ShowSaveFileDialog(callback: TSDL_DialogFileCallback; userdata: Pointer; window: PSDL_Window;
  filters: PSDL_DialogFileFilter; nfilters: LongInt; default_location: PAnsiChar); cdecl; external SDL3LIB;

function SDL_CreateRenderer(window: PSDL_Window; name: PAnsiChar): PSDL_Renderer; cdecl; external SDL3LIB;
procedure SDL_DestroyRenderer(renderer: PSDL_Renderer); cdecl; external SDL3LIB;
function SDL_SetRenderVSync(renderer: PSDL_Renderer; vsync: LongInt): Boolean; cdecl; external SDL3LIB;
function SDL_SetRenderLogicalPresentation(renderer: PSDL_Renderer; w, h: LongInt; mode: LongInt): Boolean; cdecl; external SDL3LIB;
function SDL_ConvertEventToRenderCoordinates(renderer: PSDL_Renderer; event: PSDL_Event): Boolean; cdecl; external SDL3LIB;
function SDL_SetRenderClipRect(renderer: PSDL_Renderer; rect: PSDL_Rect): Boolean; cdecl; external SDL3LIB;
function SDL_StartTextInput(window: PSDL_Window): Boolean; cdecl; external SDL3LIB;
function SDL_StopTextInput(window: PSDL_Window): Boolean; cdecl; external SDL3LIB;
function SDL_SetRenderScale(renderer: PSDL_Renderer; scaleX, scaleY: Single): Boolean; cdecl; external SDL3LIB;

function SDL_PollEvent(event: PSDL_Event): Boolean; cdecl; external SDL3LIB;

function SDL_SetRenderDrawColor(renderer: PSDL_Renderer; r, g, b, a: UInt8): Boolean; cdecl; external SDL3LIB;
function SDL_SetRenderDrawBlendMode(renderer: PSDL_Renderer; blendMode: UInt32): Boolean; cdecl; external SDL3LIB;
function SDL_RenderClear(renderer: PSDL_Renderer): Boolean; cdecl; external SDL3LIB;
function SDL_RenderPresent(renderer: PSDL_Renderer): Boolean; cdecl; external SDL3LIB;
function SDL_RenderFillRect(renderer: PSDL_Renderer; rect: PSDL_FRect): Boolean; cdecl; external SDL3LIB;
function SDL_RenderFillRects(renderer: PSDL_Renderer; rects: PSDL_FRect; count: LongInt): Boolean; cdecl; external SDL3LIB;
function SDL_RenderRect(renderer: PSDL_Renderer; rect: PSDL_FRect): Boolean; cdecl; external SDL3LIB;
function SDL_RenderLine(renderer: PSDL_Renderer; x1, y1, x2, y2: Single): Boolean; cdecl; external SDL3LIB;
function SDL_RenderGeometry(renderer: PSDL_Renderer; texture: PSDL_Texture; vertices: PSDL_Vertex;
  num_vertices: LongInt; indices: PLongInt; num_indices: LongInt): Boolean; cdecl; external SDL3LIB;
function SDL_RenderDebugText(renderer: PSDL_Renderer; x, y: Single; str: PAnsiChar): Boolean; cdecl; external SDL3LIB;

function SDL_RenderReadPixels(renderer: PSDL_Renderer; rect: PSDL_Rect): PSDL_Surface; cdecl; external SDL3LIB;
function SDL_SaveBMP(surface: PSDL_Surface; file_: PAnsiChar): Boolean; cdecl; external SDL3LIB;
procedure SDL_DestroySurface(surface: PSDL_Surface); cdecl; external SDL3LIB;

function SDL_GetTicksNS: UInt64; cdecl; external SDL3LIB;
procedure SDL_Delay(ms: UInt32); cdecl; external SDL3LIB;

implementation

end.
