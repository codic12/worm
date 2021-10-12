use crate::args::Args;
use anyhow::{bail, Context, Result};
use clap::Clap;

mod args;
mod ewmh;
mod ipc;
mod wm;

pub const NAME: &'static str = "worm";
pub const CONFIG_FILE: &'static str = "config";

fn exec_config(args: &mut Args) -> Result<()> {
    let config = args.config.get_or_insert_with(|| {
        let mut config_dir = dirs::config_dir().unwrap();
        config_dir.push(NAME);
        let mut config = config_dir.clone();
        config.push(CONFIG_FILE);
        config
    });

    if !config.exists() {
        bail!("config file does not exist");
    }

    std::process::Command::new(config)
        .spawn()
        .context("warn: failed to run config file")?;

    Ok(())
}

fn main() -> Result<()> {
    let mut args = Args::parse();
    // exec auto start script
    exec_config(&mut args)?;
    // get auto_start file location
    let (conn, scrno) = x11rb::connect(None).unwrap();

    let mut manager = wm::WindowManager::new(&conn, scrno)
        .context("\x1b[31mfatal error while connecting: \x1b[0m")?;
    manager.event_loop();
    Ok(())
}
