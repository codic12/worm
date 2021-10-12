use std::path::PathBuf;

use clap::Clap;

#[derive(Clap)]
#[clap(
    version = "0.1.0",
    author = "Aniket Prajapati <contact@aniketprajapati.me>"
)]
pub struct Args {
    /// Sets a custom config file. Could have been an Option<T> with no default too
    #[clap(short, long)]
    pub config: Option<PathBuf>,
}
