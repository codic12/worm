fn main() {
    println!("cargo:rustc-link-lib=X11"); // -lX11
    println!("cargo:rustc-link-lib=X11-xcb"); // -lX11-xcb
    println!("cargo:rustc-link-lib=Xft"); // -lXft
}