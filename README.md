
# worm <img src=logo.svg width=25 height=25>
Worm is a tiny, dynamic, tag-based window manager written in the Nim language.
It supports both a floating mode and master-stack tiling with gaps and struts.
Check out the screenshots on the wiki for some examples of how it looks.

## build / install
Install Nim >= 1.4.0, for example through Choosenim. Clone this directory and run
```
$ nimble build -d:release --gc:arc
```
And you should end up with two binaries; strip and use!

Alternatively, for users of the Arch Linux distribution, you can use the AUR package worm-git.

## License
Licensed under the MIT license. See the LICENSE file for more info.
