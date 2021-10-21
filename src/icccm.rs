extern crate x11rb;
use protocol::xproto;
use protocol::xproto::ConnectionExt;
use x11rb::*;

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

pub enum Icccm {
    WMProtocols,
    WMDeleteWindow,
    Last,
}

pub fn get_icccm_atoms<C>(conn: &C) -> Result<[xproto::Atom; Icccm::Last as usize]>
where
    C: connection::Connection,
{
    Ok([
        conn.intern_atom(false, b"WM_PROTOCOLS")?.reply()?.atom,
        conn.intern_atom(false, b"WM_DELETE_WINDOW")?.reply()?.atom,
    ])
}
