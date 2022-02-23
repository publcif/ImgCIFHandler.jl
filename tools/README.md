# imgCIF Tools

## `image_test.jl`

This program runs a series of tests on an imgCIF file. 

### Installation

1. If working with CBF files, install [cbflib](https://github.com/yayahjb/cbflib): see installation instructions for cbflib. If
on a Linux system, a pre-packaged version is likely available. For example, on Debian/Ubuntu, `apt-get install libcbf1` is
sufficient.
2. [Install Julia](https://julialang.org/downloads)
3. Start Julia, at the prompt type `]` to get the package manager
4. Install prerequisite packages by typing `add <packagename>`. You will need to add `CrystalInfoFramework`,
`Sixel`,`ImageInTerminal`, `Colors` , `ImageContrastAdjustment`,`ArgParse` and `URIs`.
5. Install `ImgCIFHandler`: still at the package prompt, type `add https://github.com/jamesrhester/ImgCIFHandler.jl`
6. Exit the package manager (`backspace`) and then Julia (`Ctrl-D` or `exit()`).
7. Copy `image_test.jl` from here to a convenient location.

### Usage

For help, run `julia image_test.jl --help` after installation.
