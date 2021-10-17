extern crate x11;
extern crate x11rb;

use x11::xlib;
use x11rb::connection::Connection;

pub mod ewmh;
pub mod ipc;
pub mod wm;

fn main() {
    let xlib_conn = unsafe { xlib::XOpenDisplay(std::ptr::null()) };
    let mut config_dir = dirs::config_dir().unwrap();
    config_dir.push("worm");
    let mut autostart = config_dir.clone();
    autostart.push("autostart");
    match std::process::Command::new(autostart).spawn() {
        Ok(_) => {}
        Err(_) => eprintln!("warn: failed to run autostart"),
    }
    let (conn, scrno) = x11rb::connect(None).unwrap();
    let conn = unsafe {
        x11rb::xcb_ffi::XCBConnection::from_raw_xcb_connection(
            x11::xlib_xcb::XGetXCBConnection(xlib_conn),
            false,
        )
        .unwrap()
    };
    let mut manager = match wm::WindowManager::new(&conn, 0, xlib_conn) {
        // TODO pass real screen.
        Ok(manager) => manager,
        Err(e) => {
            eprintln!("\x1b[31mfatal error while connecting: {}\x1b[0m", e);
            std::process::exit(1);
        }
    };
    manager.event_loop();
}
