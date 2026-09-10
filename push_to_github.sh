#!/usr/bin/env bash
# push_to_github.sh - Helper script to authenticate, create, and push day-01-linux-processes to GitHub

set -e

GH_USER="isswansalty-tech"
REPO_NAME="day-01-linux-processes"

echo "============================================================"
echo "   GitHub Deployment Helper: ${GH_USER}/${REPO_NAME}        "
echo "============================================================"

# Ensure origin remote is set
git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/${GH_USER}/${REPO_NAME}.git"

echo "[*] Configured remote origin: https://github.com/${GH_USER}/${REPO_NAME}.git"

# Check if GitHub CLI is installed and authenticated
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
    echo "[+] GitHub CLI (gh) is authenticated as $(gh api user --jq .login 2>/dev/null || echo "$GH_USER")!"
    
    # Check if repo exists on GitHub
    if ! gh repo view "${GH_USER}/${REPO_NAME}" &>/dev/null; then
        echo "[*] Creating remote repository on GitHub: ${GH_USER}/${REPO_NAME}..."
        gh repo create "${GH_USER}/${REPO_NAME}" --public --source=. --remote=origin --push
        echo "============================================================"
        echo "[✓] SUCCESS: Created repository and pushed to GitHub!"
        echo "    URL: https://github.com/${GH_USER}/${REPO_NAME}"
        echo "============================================================"
        exit 0
    else
        echo "[*] Remote repository exists. Pushing main branch..."
        git push -u origin main
        echo "============================================================"
        echo "[✓] SUCCESS: Pushed commits to https://github.com/${GH_USER}/${REPO_NAME}!"
        echo "============================================================"
        exit 0
    fi
fi

# Fallback: interactive guidance
echo ""
echo "[!] GitHub authentication is required to push to https://github.com/${GH_USER}/${REPO_NAME}."
echo ""
echo "Please select your authentication method:"
echo "  1) Login with GitHub CLI (gh auth login) [RECOMMENDED]"
echo "  2) Provide GitHub Personal Access Token (PAT)"
echo "  3) Push via SSH key (git@github.com:${GH_USER}/${REPO_NAME}.git)"
echo ""
read -r -p "Select option [1-3]: " AUTH_CHOICE

case "$AUTH_CHOICE" in
    1)
        gh auth login
        if ! gh repo view "${GH_USER}/${REPO_NAME}" &>/dev/null; then
            gh repo create "${GH_USER}/${REPO_NAME}" --public --source=. --remote=origin --push
        else
            git push -u origin main
        fi
        echo "[✓] Repository successfully pushed!"
        ;;
    2)
        read -r -s -p "Enter your GitHub Personal Access Token (PAT): " PAT_TOKEN
        echo ""
        if [ -z "$PAT_TOKEN" ]; then
            echo "[!] Token cannot be empty."
            exit 1
        fi
        # Create repo via API if it doesn't exist
        curl -s -H "Authorization: token ${PAT_TOKEN}" \
             -d "{\"name\":\"${REPO_NAME}\",\"description\":\"Day 1: Linux Process Fundamentals & Lifecycle\",\"private\":false}" \
             https://api.github.com/user/repos >/dev/null 2>&1 || true
        
        git push "https://${GH_USER}:${PAT_TOKEN}@github.com/${GH_USER}/${REPO_NAME}.git" main
        echo "[✓] Successfully pushed to https://github.com/${GH_USER}/${REPO_NAME}!"
        ;;
    3)
        git remote set-url origin "git@github.com:${GH_USER}/${REPO_NAME}.git"
        git push -u origin main
        echo "[✓] Successfully pushed via SSH!"
        ;;
    *)
        echo "[!] Invalid option selected."
        exit 1
        ;;
esac
