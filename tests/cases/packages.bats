#!/bin/bash

# This opt-in suite uses real packages in fresh, online provisioning clones.
# The catalogue is the inventory: adding or renaming a package needs no test edit.
# It checks package-manager registration, not application-specific runtime health.
# shellcheck disable=SC2154

setup() {

    [ -r /etc/dotfiles-test-image ] && [ "${DOTFILES_TEST_GUEST:-}" = 1 ]
    [ "$(id -un)" = dotfiles ]
    sudo -n true

    root=$DOTFILES_CANDIDATE
    case "$(uname -s)" in
        Darwin) platform=macos ;;
        *) platform=debian ;;
    esac

    fail() { printf '%s\n' "$*" >&2; return 1; }

    # Share catalogue parsing and architecture filtering, not package assertions.
    # shellcheck source=os/menu_catalog.sh
    source "$root/os/menu_catalog.sh"
    load_catalog

}

function packages__catalogue__ready_routes_install_and_rerun { # @test

    local index selection='' kind package receipt brew=''
    selected=()

    if [ -n "${DOTFILES_TEST_FEATURES:-}" ]; then
        selection=$DOTFILES_TEST_FEATURES
        IFS=, read -r -a selected <<< "$selection"
    else
        for ((index = 0; index < ${#feature_ids[@]}; index++)); do
            [ "${feature_status[$index]}" = ready ] || continue
            # Full LaTeX takes many gigabytes; opt in explicitly.
            [ "${feature_ids[$index]}" != 'LaTeX (full TeX Live)' ] || continue
            selected+=("${feature_ids[$index]}")
            selection="${selection:+$selection,}${feature_ids[$index]}"
        done
    fi

    [ -n "$selection" ] || skip 'No implemented routes for this platform.'
    build_plan

    /bin/bash "$root/dotfiles" install --only "$selection" --yes --backup

    # The standalone Firefox script installs a real package rather than an
    # APT step in the catalogue, so verify its receipt independently.
    case ",$selection," in
        *,Firefox,*)
            if [ "$platform" = debian ]; then
                [ "$(dpkg-query -W -f='${Status}' firefox)" = 'install ok installed' ]
                apt-cache policy firefox | grep -Fq 'https://packages.mozilla.org/apt'
            fi
            ;;
    esac

    if [ "$platform" = macos ]; then
        # Login profiles need not have run since Homebrew was installed.
        # shellcheck source=os/install_actions.sh
        source "$root/os/install_actions.sh"
        brew=$(find_brew) || true
    fi

    for ((index = 0; index < ${#plan_kinds[@]}; index++)); do
        kind=${plan_kinds[$index]}
        package=${plan_values[$index]}

        case "$kind" in
            brew|cask)
                if [ "$kind" = brew ]; then
                    receipt=$("$brew" list --formula --versions "$package")
                else
                    receipt=$("$brew" list --cask --versions "$package")
                fi
                [ -n "$receipt" ]
                ;;
            tap) "$brew" tap | grep -Fxq "$package" ;;
            apt)
                receipt=$(dpkg-query -W -f='${Status}' "$package")
                [ "$receipt" = 'install ok installed' ]
                ;;
        esac
    done

    /bin/bash "$root/dotfiles" install --only "$selection" --yes --backup

    # The i3 adapter has a real X11 smoke check, separate from package receipts.
    for ((index = 0; index < ${#plan_kinds[@]}; index++)); do
        if [ "${plan_kinds[$index]}/${plan_values[$index]}" = script/os/install_i3.sh ]; then
            sudo apt-get install -y --no-install-recommends xvfb xterm
            /bin/bash "$root/tests/helpers/i3-session.sh"
        fi
    done

}

function packages__latex__typesets_pdf_and_renders_math_preview { # @test

    # A real typesetting smoke test is deliberately limited to an explicit
    # LaTeX package run; routine suites use synthetic, catalogue-driven tests.
    case ",${DOTFILES_TEST_FEATURES:-}," in
        *,'LaTeX (full TeX Live)',*) ;;
        *) skip 'Explicitly select LaTeX (full TeX Live) to exercise the TeX installation.' ;;
    esac

    scratch=$(mktemp -d)
    # Bats executes this test in a disposable VM; remove the temporary document.
    trap 'rm -rf "$scratch"' RETURN

    # MacTeX installs the standard TeX Live PATH entry for a new login shell.
    # Make that path available now as this test process predates installation.
    if [ "$platform" = macos ]; then
        PATH="/Library/TeX/texbin:$PATH"
        export PATH
    fi

    cat > "$scratch/example.tex" <<'TEX'
\documentclass{article}
\begin{document}
A short example: $E=mc^2$.
\end{document}
TEX

    cd "$scratch" || return 1
    pdflatex -interaction=nonstopmode -halt-on-error example.tex
    [ -s example.pdf ]
    latex -interaction=nonstopmode -halt-on-error example.tex
    dvipng -o example.png example.dvi
    [ -s example.png ]

}
