icons:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    export PATH="$HOME/.cargo/bin:$PATH"

    mkdir -p assets/icons/png
    icons=(assets/icons/svg/*.svg)

    if ((${#icons[@]} == 0)); then
        echo "No SVG icons found in assets/icons/svg" >&2
        exit 1
    fi

    for icon in "${icons[@]}"; do
        filename="$(basename "${icon%.svg}")"
        resvg --stylesheet assets/icons/icons.css "$icon" "assets/icons/png/${filename}.png"
    done
