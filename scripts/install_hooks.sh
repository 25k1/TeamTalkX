#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
hook="$(git rev-parse --git-path hooks)/pre-push"
mkdir -p "$(dirname "$hook")"
cat > "$hook" <<'EOF'
#!/usr/bin/env bash
exec "$(git rev-parse --show-toplevel)/scripts/check.sh"
EOF
chmod +x "$hook"
echo "Installed $hook: every git push runs scripts/check.sh first."
echo "Skip it once with: git push --no-verify"
