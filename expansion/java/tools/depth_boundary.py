#!/usr/bin/env python3
"""Requests for every nesting level near the Java SDK's limit, built exactly as
sweeps/depth_sweep.py builds them (same base transaction, same mutation).

Usage: depth_boundary.py bases.json OUT_requests.jsonl
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "sweeps"))
import depth_sweep  # noqa: E402

depth_sweep.NS = list(range(90, 101)) + [246, 247]
depth_sweep.AUTH_NS = list(range(185, 199)) + [490, 491]
depth_sweep.main()
