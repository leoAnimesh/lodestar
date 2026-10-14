#!/bin/bash
# @lodestar.schemaVersion 1
# @lodestar.title Show Local IP Address
# @lodestar.mode compact
# @lodestar.icon 🌐
# @lodestar.keywords network,ip

ipconfig getifaddr en0 || ipconfig getifaddr en1 || echo "No active interface"
