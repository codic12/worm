extern crate x11rb;

use protocol::xproto;
use protocol::xproto::ConnectionExt;
use x11rb::*;

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

pub enum IPC {
    ClientMessage,
    KillActiveClient,
    SwitchTag,
    BorderPixel,
    BorderWidth,
    Last,
}

// Lots of these atoms we don't use, like the IPC ones. Instead, we use the offset in the IPC enum. Need to figure out better way to manage this.

pub fn get_ipc_atoms<C>(conn: &C) -> Result<[xproto::Atom; IPC::Last as usize]>
where
    C: connection::Connection,
{
    // see notes on ewmh.rs, exact same thing here

    Ok([
        conn.intern_atom(false, b"_WORM_CLIENT_MESSAGE")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_WORM_KILL_ACTIVE_CLIENT")?
            .reply()?
            .atom,
        conn.intern_atom(false, b"_WORM_SWITCH_TAG")?.reply()?.atom,
        conn.intern_atom(false, b"_WORM_BORDER_PIXEL")?.reply()?.atom,
        conn.intern_atom(false, b"_WORM_BORDER_WIDTH")?.reply()?.atom,
    ])
}
