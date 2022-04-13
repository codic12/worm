import
  x11/[xlib, x ]

converter toXBool(x: bool): XBool = x.XBool
# converter toBool(x: XBool): bool = x.bool

type
  NetAtom* = enum
    NetActiveWindow               = "_NET_ACTIVE_WINDOW",
    NetSupported                  = "_NET_SUPPORTED",
    NetSystemTray                 = "_NET_SYSTEM_TRAY_S0",
    NetSystemTrayOP               = "_NET_SYSTEM_TRAY_OPCODE",
    NetSystemTrayOrientation      = "_NET_SYSTEM_TRAY_ORIENTATION",
    NetSystemTrayOrientationHorz  = "_NET_SYSTEM_TRAY_ORIENTATION_HORZ",
    NetWMName                     = "_NET_WM_NAME",
    NetWMState                    = "_NET_WM_STATE",
    NetWMStateAbove               = "_NET_WM_STATE_ABOVE",
    NetWMStateMaximizedVert       = "_NET_WM_STATE_MAXIMIZED_VERT",
    NetWMStateMaximizedHorz       = "_NET_WM_STATE_MAXIMIZED_HORZ",
    NetWMStateSticky              = "_NET_WM_STATE_STICKY",
    NetWMStateModal               = "_NET_WM_STATE_MODAL",
    NetSupportingWMCheck          = "_NET_SUPPORTING_WM_CHECK",
    NetWMStateFullScreen          = "_NET_WM_STATE_FULLSCREEN",
    NetClientList                 = "_NET_CLIENT_LIST",
    NetWMStrutPartial             = "_NET_WM_STRUT_PARTIAL",
    NetWMWindowType               = "_NET_WM_WINDOW_TYPE",
    NetWMWindowTypeNormal         = "_NET_WM_WINDOW_TYPE_NORMAL",
    NetWMWindowTypeDialog         = "_NET_WM_WINDOW_TYPE_DIALOG",
    NetWMWindowTypeUtility        = "_NET_WM_WINDOW_TYPE_UTILITY",
    NetWMWindowTypeToolbar        = "_NET_WM_WINDOW_TYPE_TOOLBAR",
    NetWMWindowTypeSplash         = "_NET_WM_WINDOW_TYPE_SPLASH",
    NetWMWindowTypeMenu           = "_NET_WM_WINDOW_TYPE_MENU",
    NetWMWindowTypeDropdownMenu   = "_NET_WM_WINDOW_TYPE_DROPDOWN_MENU",
    NetWMWindowTypePopupMenu      = "_NET_WM_WINDOW_TYPE_POPUP_MENU",
    NetWMWindowTypeTooltip        = "_NET_WM_WINDOW_TYPE_TOOLTIP",
    NetWMWindowTypeNotification   = "_NET_WM_WINDOW_TYPE_NOTIFICATION",
    NetWMWindowTypeDock           = "_NET_WM_WINDOW_TYPE_DOCK",
    NetWMWindowTypeDesktop        = "_NET_WM_WINDOW_TYPE_DESKTOP",
    NetWMDesktop                  = "_NET_WM_DESKTOP",
    NetDesktopViewport            = "_NET_DESKTOP_VIEWPORT",
    NetNumberOfDesktops           = "_NET_NUMBER_OF_DESKTOPS",
    NetCurrentDesktop             = "_NET_CURRENT_DESKTOP",
    NetDesktopNames               = "_NET_DESKTOP_NAMES",
    NetFrameExtents               = "_NET_FRAME_EXTENTS"

  IpcAtom* = enum
    IpcClientMessage        = "WORM_IPC_CLIENT_MESSAGE",
    IpcBorderActivePixel    = "WORM_IPC_BORDER_ACTIVE_PIXEL",
    IpcBorderInactivePixel  = "WORM_IPC_BORDER_INACTIVE_PIXEL",
    IpcBorderWidth          = "WORM_IPC_BORDER_WIDTH",
    IpcFrameActivePixel     = "WORM_IPC_FRAME_ACTIVE_PIXEL",
    IpcFrameInactivePixel   = "WORM_IPC_FRAME_INACTIVE_PIXEL",
    IpcFrameHeight          = "WORM_IPC_FRAME_HEIGHT",
    IpcTextActivePixel      = "WORM_IPC_TEXT_ACTIVE_PIXEL",
    IpcTextInactivePixel    = "WORM_IPC_TEXT_INACTIVE_PIXEL",
    IpcTextFont             = "WORM_IPC_TEXT_FONT",
    IpcTextOffset           = "WORM_IPC_TEXT_OFFSET",
    IpcKillClient           = "WORM_IPC_KILL_CLIENT",
    IpcCloseClient          = "WORM_IPC_CLOSE_CLIENT",
    IpcSwitchTag            = "WORM_IPC_SWITCH_TAG",
    IpcAddTag               = "WORM_IPC_ADD_TAG",
    IpcRemoveTag            = "WORM_IPC_REMOVE_TAG"
    IpcLayout               = "WORM_IPC_LAYOUT",
    IpcGaps                 = "WORM_IPC_GAPS",
    IpcMaster               = "WORM_IPC_MASTER",
    IpcStruts               = "WORM_IPC_STRUTS",
    IpcMoveTag              = "WORM_IPC_MOVE_TAG",
    IpcFrameLeft            = "WORM_IPC_FRAME_LEFT",
    IpcFrameCenter          = "WORM_IPC_FRAME_CENTER",
    IpcFrameRight           = "WORM_IPC_FRAME_RIGHT",
    IpcFloat                = "WORM_IPC_FLOAT",
    IpcButtonOffset         = "WORM_IPC_BUTTON_OFFSET",
    IpcButtonSize           = "WORM_IPC_BUTTON_SIZE",
    IpcRootMenu             = "WORM_IPC_ROOT_MENU",
    IpcCloseActivePath      = "WORM_IPC_CLOSE_ACTIVE_PATH",
    IpcCloseInactivePath    = "WORM_IPC_CLOSE_INACTIVE PATH",
    IpcMaximizeActivePath   = "WORM_IPC_MAXIMIZE_ACTIVE_PATH",
    IpcMaximizeInactivePath = "WORM_IPC_MAXIMIZE_INACTIVE_PATH",
    IpcMinimizeACtivePath   = "WORM_IPC_MINIMIZE_ACTIVE_PATH",
    IpcMinimizeInactivePath = "WORM_IPC_MINIMIZE_INACTIVE_PATH",
    IpcMaximizeClient       = "WORM_IPC_MAXIMIZE_CLIENT",
    IpcMinimizeClient       = "WORM_IPC_MINIMIZE_CLIENT",
    IpcDecorationDisable  = "WORM_IPC_DECORATION_DISABLE"

func getNetAtoms*(dpy: ptr Display): array[NetAtom, Atom] =
  for atom in NetAtom:
    result[atom] = dpy.XInternAtom(($atom).cstring, false)

func getIpcAtoms*(dpy: ptr Display): array[IpcAtom, Atom] =
  for atom in IpcAtom:
    result[atom] = dpy.XInternAtom(($atom).cstring, false)
