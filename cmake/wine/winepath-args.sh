# winepath-args.sh — translate Linux paths in XDK-tool args to Wine drive paths.
# Sourced by the cl-wine / link-wine / lib-wine / imagexex-wine wrappers.
# Override the translator in tests with WINEPATH_FN=my_stub.

to_win_path() {
    if [ -n "${WINEPATH_FN:-}" ]; then "$WINEPATH_FN" "$1"; return; fi
    wine winepath -w "$1" 2>/dev/null | tr -d '\r'
}

translate_one() {
    local a="$1"
    case "$a" in
        /Fo*|/Fd*|/Fp*|/Fe*) printf '%s' "${a:0:3}"; to_win_path "${a:3}" ;;
        -I*)        printf -- '-I';        to_win_path "${a:2}" ;;
        /OUT:*)     printf '/OUT:';        to_win_path "${a#/OUT:}" ;;
        /IN:*)      printf '/IN:';         to_win_path "${a#/IN:}" ;;
        /CONFIG:*)  printf '/CONFIG:';     to_win_path "${a#/CONFIG:}" ;;
        /PDB:*)     printf '/PDB:';        to_win_path "${a#/PDB:}" ;;
        /IMPLIB:*)  printf '/IMPLIB:';     to_win_path "${a#/IMPLIB:}" ;;
        /LIBPATH:*) printf '/LIBPATH:';    to_win_path "${a#/LIBPATH:}" ;;
        # /I include path: anchor to /I/<abs> or /I.<rel> so link flags that
        # merely start with /I (/INCREMENTAL, /INCLUDE, /IGNORE) are NOT paths.
        /I/*|/I.*)  printf '/I';           to_win_path "${a:2}" ;;
        -*|/*)
            if [ -e "$a" ]; then to_win_path "$a"; else printf '%s' "$a"; fi ;;
        *)
            if [ -e "$a" ] || case "$a" in */*) true ;; *) false ;; esac; then
                to_win_path "$a"
            else
                printf '%s' "$a"
            fi ;;
    esac
}

translate_args() {
    TRANSLATED_ARGS=()
    local a tok rsp tmp
    for a in "$@"; do
        case "$a" in
            @*)
                rsp="${a#@}"; tmp="$(mktemp)"
                while IFS= read -r tok; do
                    [ -n "$tok" ] || continue
                    translate_one "$tok"; printf '\n'
                done < <(xargs -n1 printf '%s\n' < "$rsp") > "$tmp"
                TRANSLATED_ARGS+=( "@$(to_win_path "$tmp")" )
                ;;
            *)
                TRANSLATED_ARGS+=( "$(translate_one "$a")" )
                ;;
        esac
    done
}
