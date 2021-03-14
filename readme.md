Chime Converter
===========================
About:
-------------
A tool for converting basic CIT packs to the [Chime format](https://github.com/emilyalexandra/chime).<br/>
Currently WIP, only functions for certain overrides.

Usage:
-------------
extract your resource pack, and rename it to in<br/>
run chime-converter.exe<br/>
copy `pack.mcmeta` and `pack.png` from `in` to `out`

Building:
-------------
<details>
  <summary>Windows</summary>

  - download and install [DMD](https://dlang.org/download.html#dmd)
  - open a command prompt and cd to the project's source code
     - (there should be a file called `dub.json` in the folder)
  - in the command prompt, run `dub`
     - should create `chime-converter.exe`
</details>

<details>
  <summary>Linux</summary>

  - download and install DMD
    - [download the latest x86_64 .deb installer](https://dlang.org/download.html#:~:text=%C2%A0-,Ubuntu/Debian,-i386)
    - `sudo apt install path_to_deb_file`
  - cd to the project's source code in a terminal
  - run `dub`
    - if you get a [symbol lookup error](https://forum.dlang.org/post/rrqff0$21cf$1@digitalmars.com), update Linux

</details>
