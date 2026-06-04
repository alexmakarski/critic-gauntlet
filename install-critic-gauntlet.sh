#!/bin/bash
# Critic Gauntlet Installer
# Copies the critic-gauntlet skill into your Claude Code skills directory.
# Run from the folder containing this script.
#
# (Optional alternative: install as a plugin via
#  /plugin marketplace add alexmakarski/critic-gauntlet
#  /plugin install critic-gauntlet@critic-gauntlet )

set -e

SKILLS_DIR="$HOME/.claude/skills"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SKILLS="$SCRIPT_DIR/skills"

if [ ! -d "$SOURCE_SKILLS/critic-gauntlet" ]; then
    echo "ERROR: No 'skills/critic-gauntlet/' folder found next to this script."
    echo "Expected: $SOURCE_SKILLS/critic-gauntlet"
    exit 1
fi

mkdir -p "$SKILLS_DIR"

echo ""
echo "Critic Gauntlet Installer"
echo "========================="
echo ""
echo "Adversarial multi-model architecture critic."
echo ""
echo "Source:     $SCRIPT_DIR"
echo "Skills dir: $SKILLS_DIR"
echo ""

if [ -d "$SKILLS_DIR/critic-gauntlet" ]; then
    echo "WARNING: an existing critic-gauntlet skill was found. It will be overwritten."
    echo ""
    read -p "Continue? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

echo "Installing skill..."
rm -rf "$SKILLS_DIR/critic-gauntlet"
cp -r "$SOURCE_SKILLS/critic-gauntlet" "$SKILLS_DIR/critic-gauntlet"
chmod +x "$SKILLS_DIR/critic-gauntlet"/*.sh

echo ""
echo "Done. critic-gauntlet skill installed."
echo ""
echo "Optional: set XAI_API_KEY and GEMINI_API_KEY to enable the Grok and Gemini critics."
echo "Restart Claude Code, then invoke the critic-gauntlet skill."
echo ""
