<img src=logo.svg align=right>

# Worm

Worm is a tiny, dynamic, tag-based window manager written in the Nim language.
It supports both a floating mode and master-stack tiling with gaps and struts.
Check out the [screenshots on the wiki](https://github.com/codic12/worm/wiki/Screenshots) for some examples of how it looks.

## Build / install

Install Nim >= 1.6.0, for example through Choosenim. Clone this repo and run

```
$ nimble build -d:release --gc:arc
```
And you should end up with two binaries; strip and use!

Alternatively, for users using Arch, you can use the AUR package worm-git.

```
$ yay -S worm-git
```

## Configuration

### Autostart

Worm will try to execute the file `~/.config/worm/rc` on startup.
Simply create it as a shell-script to execute your favorite applications with
worm.
(don't forget to make it executable).

An example can be found [here](/examples/rc).

### Keybindings

Worm does not have a built-in keyboard mapper, so you should use something like
[sxhkd](https://github.com/baskerville/sxhkd).
Please read [the docs](docs/wormc.md) to understand how wormc works before
writing your own sxhkdrc.

An example sxhkdrc can be found [here](/examples/sxhkdrc).

## License

Licensed under the MIT license. See the LICENSE file for more info.

## Credits

Thanks to [phisch](https://github.com/phisch) for making the logo!

Thanks to everyone else that's opened an issue, a PR, or just tried out worm. 

