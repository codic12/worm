extern crate x11rb;

pub mod ewmh;
pub mod ipc;
pub mod wm;

fn main() {
    let mut config_dir = dirs::config_dir().unwrap();
    config_dir.push("worm");
    let mut autostart = config_dir.clone();
    autostart.push("autostart");
    match std::process::Command::new(autostart).spawn() {
        Ok(_) => {}
        Err(_) => eprintln!("warn: failed to run autostart"),
    }
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
