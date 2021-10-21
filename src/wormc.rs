extern crate x11rb;
use connection::Connection;
use protocol::xproto::{self, ConnectionExt};
use x11rb::*;
pub mod ipc;

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();

    let (conn, scrno) = x11rb::connect(None)?;
    let atoms = ipc::get_ipc_atoms(&conn)?;
    let root = conn.setup().roots[scrno].root;
    conn.send_event(
        false,
        root,
        xproto::EventMask::SUBSTRUCTURE_NOTIFY,
        xproto::ClientMessageEvent::new(
            32,
            root,
            atoms[ipc::IPC::ClientMessage as usize],
            match args[1].as_ref() {
                "kill-active-client" => [ipc::IPC::KillActiveClient as u32, 0, 0, 0, 0],
                "close-active-client" => [ipc::IPC::CloseActiveClient as u32, 0, 0, 0, 0],
                "switch-tag" => [ipc::IPC::SwitchTag as u32, args[2].parse::<u32>()?, 0, 0, 0],
                "active-border-pixel" => [
                    ipc::IPC::ActiveBorderPixel as u32,
                    args[2].parse::<u32>()?,
                    0,
                    0,
                    0,
                ],
                "inactive-border-pixel" => [
                    ipc::IPC::InactiveBorderPixel as u32,
                    args[2].parse::<u32>()?,
                    0,
                    0,
                    0,
                ],
                "border-width" => [
                    ipc::IPC::BorderWidth as u32,
                    args[2].parse::<u32>()?,
                    0,
                    0,
                    0,
                ],
                "background-pixel" => [
                    ipc::IPC::BackgroundPixel as u32,
                    args[2].parse::<u32>()?,
                    0,
                    0,
                    0,
                ],
                "title-height" => [
                    ipc::IPC::TitleHeight as u32,
                    args[2].parse::<u32>()?,
                    0,
                    0,
                    0,
                ],
                "switch-active-window-tag" => [
                    ipc::IPC::SwitchActiveWindowTag as u32,
                    args[2].parse::<u32>()?,
                    0,
                    0,
                    0,
                ],
                _ => unreachable!(),
            },
        ),
    )?
    .check()?;
    conn.flush()?;
    Ok(())
}
