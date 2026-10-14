#!/bin/bash
# @lodestar.schemaVersion 1
# @lodestar.title Disk Usage
# @lodestar.mode fullOutput
# @lodestar.icon 💽
# @lodestar.description Free space on mounted volumes

df -h | grep -E '^(Filesystem|/dev/)'
