#!/bin/bash
# Generic Data Viewer Entry Point
# Delegates to version-specific implementation

set -e

# Detect version (default: v72)
VERSION=${EPH_VERSION:-"v72"}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_SCRIPT="$SCRIPT_DIR/$VERSION/viewer.sh"

if [ ! -f "$VERSION_SCRIPT" ]; then
    echo "❌ Error: Version $VERSION not found"
    echo "   Available versions:"
    ls -1d "$SCRIPT_DIR"/v*/ 2>/dev/null | xargs -n1 basename || echo "   (none)"
    exit 1
fi

echo "👁️  EPH Data Viewer (version: $VERSION)"
echo ""

# Execute version-specific script
exec "$VERSION_SCRIPT" "$@"
