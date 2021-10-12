# worm
*worm* is a floating, tag-based window manager for X11. It is written in the Rust programming language, using the X11RB library.

A window manager is a program that manages windows, by letting the user move them, resize them, drawing titlebars, etc. It also provides functionality like workspaces and supports client side protocols, like EWMH and ICCCM in the X11 case. This lets the program do things like fullscreen itself.

A floating window manager, like the \*box family of window managers as well as Windows and MacOS (and of course worm), simply draws windows wherever they ask to be drawn and lets the user move them around. This is in contrast to a tiling window manager, which draws windows in a specific layout. Worm plans to eventually gain the ability to tile.

Tags are a unique concept borrowed from window managers like DWM and Awesome. Instead of workspaces having windows, windows have tags. This is a very unique concept. You can view 3 separate tags at a time, or have a window on 3 separate tags. Right now only the use case of being used like workspaces is supported, but internally the foundation for tags is there; just needs to be exposed to the user with IPC support.

## Building
Building requires cargo/rust to be installed on your system.
Simply clone this git repository and build with cargo:
```
$ git clone https://github.com/codic12/worm
$ cd worm
$ cargo build --release
```

You'll find the binaries in the `target/release` directory.

## Installing
After building, copy `worm` and `wormc` to a directory listed in the PATH variable.
(typically you'd put it into `/usr/local/bin`)

```
$ sudo cp target/release/{worm,wormc} /usr/local/bin/
```

For those of you using a display manager, you can copy the `worm.desktop` file located in `assets` to your xsessions directoy.

```
$ sudo cp assets/worm.desktop /usr/share/xsessions/
```

If you're running an Arch-based distribution, you can use the [worm-git](https://aur.archlinux.org/packages/worm-git/) AUR package to build and install worm.


## Autostart / configuration
Worm will try to execute the file `~/.config/worm/autostart` on startup.  
Simply create it as a shell-script to execute your favorite applications with worm.  
(don't forget to make it executable)

An example can be found [here](examples/autostart)

## Screenshots
Check the wiki page.

## Contribute
Use it! Spread the word! Report issues! Submit pull requests!

## License
Worm is distributed under the [MIT License](LICENSE); you may obtain a copy [here](https://mit-license.org/).
