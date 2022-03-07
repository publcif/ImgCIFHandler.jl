![Testing](https://github.com/jamesrhester/ImgCIFHandler.jl/workflows/Tests/badge.svg)

# ImgCIFHandler

This Julia package provides a single function `imgload` which will load raw
data images referenced by imgCIF files. imgCIF is a raw data standard developed
by the International Union of Crystallography, and recently enhanced with data
pointers so that the raw data can be preserved outside of the imgCIF file 
itself.

# Installation

## Prerequisites

You must have [CBFLib](https://github.com/yayahjb/cbflib) installed. Packages exist for some Linux distributions,
e.g. `libcbf1` on Debian and Ubuntu.

The programs `tar` and `curl` must be installed, as well as `gzip` and `bunzip2`. This requirement may be removed
in the future.

## Installation

To install this package, at the Julia package prompt (reached by typing `]` at the Julia prompt) type `add ImgCIFHandler`.

# Use

After installation, typing 'using ImgCIFHandler' will import the package. A single function `imgload` will be in scope. This function can be used to
access raw data stored using pointers within imgCIF files. The example file [`b4_master.cif`](test/testfiles/b4_master.cif) contains such pointers.
For example, to read the raw data array labelled `ext1` in `b4_master.cif` the following call is used:

```julia
x = imgload("b4_master.cif","ext1")
```

# Supported external formats

This release supports `HDF5`, `CBF`, and `SMV` (ADSC) formats, as well as Tar archives (optionally compressed using Bzip2 or Gzip) or 
Zip archives containing files in those formats. In all cases the format stated by the imgCIF file is used.
