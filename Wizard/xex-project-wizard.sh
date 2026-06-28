#!/usr/bin/env bash
# Linux GUI wizard for Xbox 360 XEX project scaffolding.
# Requires yad (preferred) or zenity, plus cmake in PATH.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(dirname "$SCRIPT_DIR")"
SCAFFOLD="$SCRIPT_DIR/xex-scaffold.cmake"
TITLE="Xbox 360 XEX Project Wizard"

# Prefer yad (single-form), fall back to zenity (multi-step)
if   command -v yad    &>/dev/null; then GUI=yad
elif command -v zenity &>/dev/null; then GUI=zenity
else echo "Install yad or zenity" >&2; exit 1; fi

# ---- Prerequisites -----------------------------------------------------------
missing=()
command -v cmake &>/dev/null || missing+=("cmake not in PATH")
[[ -f $SCAFFOLD ]]           || missing+=("xex-scaffold.cmake not found")

if [[ ${#missing[@]} -gt 0 ]]; then
    msg=$(printf '%s\n' "${missing[@]}")
    if [[ $GUI == yad ]]; then
        yad --title="$TITLE" --image=dialog-error \
            --text="Prerequisites missing:\n$msg" --button="OK:0" || true
    else
        zenity --error --title="$TITLE" --text="Prerequisites missing:\n$msg" || true
    fi
    exit 1
fi

# ---- Collect settings --------------------------------------------------------
if [[ $GUI == yad ]]; then
    result=$(yad --title="$TITLE" --form --separator='|' \
        --field="Project name" "" \
        --field="Type:CB" "DLL!EXE" \
        --field="Entry symbol (DLL only)" "GtampEntryPoint" \
        --field="Create in folder:DIR" "$HOME" \
        --field="Use xkelib:CHK" "FALSE" \
        --field="xkelib path (optional):CDIR" "" \
        --button="Cancel:1" --button="Next:0") || exit 0
    IFS='|' read -r NAME TYPE ENTRY TARGET_DIR USE_XKE XKELIB_DIR <<< "$result"
    [[ $USE_XKE == TRUE ]] && USE_XKE=ON || USE_XKE=OFF
else
    NAME=$(zenity --entry --title="$TITLE — Project name" \
        --text="Project name:") || exit 0
    TYPE=$(zenity --list --title="$TITLE — Project type" \
        --radiolist --column="" --column="Type" TRUE DLL FALSE EXE) || exit 0
    ENTRY=$(zenity --entry --title="$TITLE — Entry symbol" \
        --text="Entry symbol (DLL only):" \
        --entry-text="GtampEntryPoint") || exit 0
    TARGET_DIR=$(zenity --file-selection --title="$TITLE — Create in folder" \
        --directory) || exit 0
    USE_XKE=OFF
    XKELIB_DIR=""
fi

# Trim any trailing pipe yad CB may add, then uppercase
TYPE="${TYPE%%|*}"
TYPE="${TYPE^^}"

# ---- Normalize name ----------------------------------------------------------
# Replace runs of non-identifier chars (spaces, hyphens, etc.) with underscores,
# then strip any leading non-alpha chars so the result is a valid C identifier.
NAME_RAW="$NAME"
NAME=$(printf '%s' "$NAME" | sed 's/[^A-Za-z0-9_]\+/_/g; s/^[^A-Za-z]*//')

if [[ -z $NAME ]]; then
    if [[ $GUI == yad ]]; then
        yad --title="$TITLE" --image=dialog-error \
            --text="'$NAME_RAW' cannot be normalized to a valid identifier." \
            --button="OK:0" || true
    else
        zenity --error --title="$TITLE" \
            --text="'$NAME_RAW' cannot be normalized to a valid identifier." || true
    fi
    exit 1
fi

# ---- Review ------------------------------------------------------------------
summary="Name:    $NAME
Type:    XEX-$TYPE
Folder:  $TARGET_DIR/$NAME
Entry:   $ENTRY
xkelib:  $([[ $USE_XKE == ON ]] && echo "yes ($XKELIB_DIR)" || echo no)"

if [[ $GUI == yad ]]; then
    yad --title="$TITLE — Review" --text="$summary" \
        --button="Cancel:1" --button="Create:0" || exit 0
else
    zenity --question --title="$TITLE — Review" --text="$summary" \
        --ok-label="Create" --cancel-label="Cancel" || exit 0
fi

# ---- Scaffold ----------------------------------------------------------------
tmplog=$(mktemp /tmp/xex-wizard-XXXXXX.log)
rc=0
cmake \
    -DNAME="$NAME" \
    -DTYPE="$TYPE" \
    -DTARGET_DIR="$TARGET_DIR" \
    -DTOOLKIT_ROOT="$TOOLKIT_ROOT" \
    -DENTRY_SYMBOL="$ENTRY" \
    -DUSE_XKELIB="$USE_XKE" \
    -DXKELIB_DIR="$XKELIB_DIR" \
    -P "$SCAFFOLD" >"$tmplog" 2>&1 || rc=$?
log=$(<"$tmplog"); rm -f "$tmplog"

if [[ $rc -ne 0 ]]; then
    if [[ $GUI == yad ]]; then
        yad --title="$TITLE — Error" --image=dialog-error \
            --text="Scaffold failed:\n\n$log" --button="OK:0" || true
    else
        zenity --error --title="$TITLE — Error" \
            --text="Scaffold failed:\n\n$log" || true
    fi
    exit 1
fi

# ---- Done --------------------------------------------------------------------
msg="Created $TARGET_DIR/$NAME\n\n$log"
if [[ $GUI == yad ]]; then
    btn=0
    yad --title="$TITLE — Done" --image=dialog-info \
        --text="$msg" --button="Open Folder:2" --button="Close:0" || btn=$?
    [[ $btn -eq 2 ]] && nohup xdg-open "$TARGET_DIR/$NAME" &>/dev/null &
else
    zenity --info --title="$TITLE — Done" --text="$msg" || true
fi
