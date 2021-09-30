extern crate x11rb;

pub mod ewmh;
pub mod ipc;
pub mod wm;

fn main() {
    let (conn, scrno) = x11rb::connect(None).unwrap();
    let mut manager = match wm::WindowManager::new(&conn, scrno) {
        Ok(manager) => manager,
        Err(e) => {
            eprintln!("\x1b[31mfatal error while connecting: {}\x1b[0m", e);
            std::process::exit(1);
        }
    };
    manager.event_loop();
}
