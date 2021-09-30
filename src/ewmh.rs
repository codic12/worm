extern crate x11rb;

use protocol::xproto;
use protocol::xproto::ConnectionExt;
use x11rb::*;

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
pub enum Net {
    ActiveWindow,
    Supported,
    SystemTray,
    SystemTrayOP,
    SystemTrayOrientation,
    SystemTrayOrientationHorz,
    WMName,
    WMState,
    WMStateAbove,
    WMStateSticky,
    WMStateModal,
    SupportingWMCheck,
    WMStateFullScreen,
    ClientList,
    WMStrutPartial,
    WMWindowType,
    WMWindowTypeNormal,
    WMWindowTypeDialog,
    WMWindowTypeUtility,
    WMWindowTypeToolbar,
    WMWindowTypeSplash,
    WMWindowTypeMenu,
    WMWindowTypeDropdownMenu,
    WMWindowTypePopupMenu,
    WMWindowTypeTooltip,
    WMWindowTypeNotification,
    WMWindowTypeDock,
    WMDesktop,
    DesktopViewport,
    NumberOfDesktops,
    CurrentDesktop,
    DesktopNames,
    FrameExtents,
    Last,
}

pub fn get_ewmh_atoms<C>(conn: &C) -> Result<[xproto::Atom; Net::Last as usize]>
where
    C: connection::Connection,
{
    // I want to do this from an array of strings later, but that is more of a pain to implement
    // because the simplest solution requires allocating on the heap and copying that to the stack;
    // I think best is to do this with a macro, every other way will have some runtime overhead I
    // guess

    Ok([
        conn.intern_atom(false, b"_NET_ACTIVE_WINDOW")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_SUPPORTED")?.reply()?.atom,
        conn.intern_atom(false, b"_NET_SYSTEM_TRAY_S0")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_SYSTEM_TRAY_OPCODE")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_SYSTEM_TRAY_ORIENTATION")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_SYSTEM_TRAY_ORIENTATION_HORZ")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_NAME")?.reply()?.atom,
        conn.intern_atom(false, b"_NET_WM_STATE")?.reply()?.atom,
        conn.intern_atom(false, b"_NET_WM_STATE_ABOVE")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_STATE_STICKY")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_STATE_MODAL")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_SUPPORTING_WM_CHECK")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_STATE_FULLSCREEN")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_CLIENT_LIST")?.reply()?.atom,
        conn.intern_atom(false, b"_NET_WM_STRUT_PARTIAL")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_WINDOW_TYPE")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_WINDOW_TYPE_NORMAL")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_WINDOW_TYPE_DIALOG")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_WINDOW_TYPE_UTILITY")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_WINDOW_TYPE_TOOLBAR")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_WINDOW_TYPE_SPLASH")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_WINDOW_TYPE_MENU")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_WINDOW_TYPE_DROPDOWN_MENU")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_WINDOW_TYPE_POPUP_MENU")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_WINDOW_TYPE_TOOLTIP")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_WINDOW_TYPE_NOTIFICATION")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_WINDOW_TYPE_DOCK")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_WM_DESKTOP")?.reply()?.atom,
        conn.intern_atom(false, b"_NET_DESKTOP_VIEWPORT")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_NUMBER_OF_DESKTOPS")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_CURRENT_DESKTOP")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_DESKTOP_NAMES")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_NET_FRAME_EXTENTS")?
            .reply()?
            .atom,
    ])
}
