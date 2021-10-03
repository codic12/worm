# worm
*worm* is a floating, tag-based window manager for X11. It is written in the Rust programming language, using the X11RB library.

A window manager is a program that manages windows, by letting the user move them, resize them, drawing titlebars, etc. It also provides functionality like workspaces and supports client side protocols, like EWMH and ICCCM in the X11 case. This lets the program do things like fullscreen itself.

A floating window manager, like the \*box family of window managers as well as Windows and MacOS (and of course worm), simply draws windows wherever they ask to be drawn and lets the user move them around. This is in contrast to a tiling window manager, which draws windows in a specific layout. Worm plans to eventually gain the ability to tile.

Tags are a unique concept borrowed from window managers like DWM and Awesome. Instead of workspaces having windows, windows have tags. This is a very unique concept. You can view 3 separate tags at a time, or have a window on 3 separate tags. Right now only the use case of being used like workspaces is supported, but internally the foundation for tags is there; just needs to be exposed to the user with IPC support.

## Get (git) the code - a refresher if needed

Depending on where you store your source code, most other git cloned projects may be in /opt.
```
$ git clone https://github.com/codic12/worm
```
## Install
```
$ cargo build --release
```
In the target/release directory you should find two binaries, `worm` and `wormc`. Put them somewhere in your path, and then launch as usual - whether with a display manager or via startx (~/.xinitrc).

Or, if you're running an Arch based system, check out the AUR package [worm-git](https://aur.archlinux.org/packages/worm-git/), kindly maintained by `moson`.

## Screenshot
![](screenshot.png)

## Contribute
Use it! Spread the word! Report issues! Submit pull requests!

## License
Worm is distributed under the [MIT License](LICENSE); you may obtain a copy [here](https://mit-license.org/).
