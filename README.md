# Nonlinear least-squares fitting in Futhark [![Build Status](https://travis-ci.org/diku-dk/lmdif.svg?branch=master)](https://travis-ci.org/diku-dk/lmdif) [![Documentation](https://futhark-lang.org/pkgs/github.com/diku-dk/lmdif/status.svg)](https://futhark-lang.org/pkgs/github.com/diku-dk/lmdif/latest/)

This repository contains a [Futhark](https://futhark-lang.org) package
for doing nonlinear least-squares fitting using the
Levenberg-Marquardt algorithm.  Its ancestry is somewhat convoluted:
the code is partially based on a
[LexiFi](https://www.lexifi.com/)-provided OCaml translation of
[MPFIT](https://www.physics.wisc.edu/~craigm/idl/cmpfit.html), which
is itself a C translation of the FORTRAN program
[`lmdif.f`](http://www.netlib.org/minpack/lmdif.f) from
[MINPACK](http://www.netlib.org/minpack/).  This package is named in
honour of that original FORTRAN program.

The porting to Futhark was done as part of a larger project while
Troels Henriksen was visiting [SimCorp](https://www.simcorp.com/).

## Installation

```
$ futhark pkg add github.com/diku-dk/lmdif
$ futhark pkg sync
```

## Usage

Usage is slightly involved.  See [this test
program](lib/github.com/diku-dk/lmdif/lmdif_tests.fut) for
an example.  You will need to write your own distance functions.  The
package [github.com/athas/distance](https://github.com/athas/distance)
might be useful.
