# cache-simulator

This project implements a 1-level cache simulator using ARMv7 Assembly. It supports multiple cache replacement policies including:

FIFO (First-In-First-Out)

LRU (Least Recently Used)

MRU (Most Recently Used)

LFU (Least Frequently Used)

MFU (Most Frequently Used)

Random Replacement

## Features include:

Support for 2-way set-associative cache

Word-aligned memory access using LDR/STR (4-byte units)

Per-level hit/miss statistics

Fully modular and policy-independent architecture

Lightweight pseudo-random generator for Random replacement

The simulator mimics realistic cache behavior and is suitable for understanding memory hierarchy, replacement algorithms, and performance trade-offs in low-level systems programming.
