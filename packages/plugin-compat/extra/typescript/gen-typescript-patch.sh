set -ex

THIS_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMP_DIR="/tmp/ts-repo"

PATCHFILE="$TEMP_DIR"/patch.tmp
JSPATCH="$THIS_DIR"/../../sources/patches/typescript.patch.ts

FIRST_PR_COMMIT="5d50de3"

HASHES=(
  # Base    # Patch   # Ranges
  "e39bdc3" "426f5a7" ">=3.2 <3.5"
  "cf7b2d4" "426f5a7" ">=3.5 <=3.6"
  "cda54b8" "426f5a7" ">3.6 <3.7"
  "e39bdc3" "2f85932" ">=3.7 <3.9"
  "551f0dd" "3af06df" ">=3.9 <=4.0.3"
  "69972a3" "cefc8b4" ">4.0.3"
)

mkdir -p "$TEMP_DIR"
if ! [[ -d "$TEMP_DIR"/clone ]]; then (
    git clone https://github.com/arcanis/typescript "$TEMP_DIR"/clone
    cd "$TEMP_DIR"/clone
    git remote add upstream https://github.com/microsoft/typescript
); fi

rm -rf "$TEMP_DIR"/builds
cd "$TEMP_DIR"/clone

git cherry-pick --abort || true

git config user.email "you@example.com"
git config user.name "Your Name"

git fetch origin
git fetch upstream

reset-git() {
  git reset --hard "$1"
  git clean -df

  npm install --before "$(git show -s --format=%ci)"
}

build-dir-for() {
  local BASE="$1"
  local PATCH="$2"

  local BUILD_DIR="$TEMP_DIR"/builds/"$BASE"

  if [[ ! -z "$PATCH" ]]; then
    BUILD_DIR="$BUILD_DIR-$PATCH"
  fi

  echo "$BUILD_DIR"
}

make-build-for() {
  local BASE="$1"
  local PATCH="$2"

  local BUILD_DIR="$(build-dir-for "$BASE" "$PATCH")"

  if [[ ! -e "$BUILD_DIR" ]]; then
    mkdir -p "$BUILD_DIR"
    reset-git "$BASE"

    if [[ ! -z "$PATCH" ]]; then
      if git merge-base --is-ancestor "$BASE" "$PATCH"; then
        git merge --no-edit "$PATCH"
      else
        git cherry-pick "$FIRST_PR_COMMIT"^.."$PATCH"
      fi
    fi

    for n in {5..1}; do
      yarn gulp local LKG
      
      if [[ $(stat -c%s lib/typescript.js) -gt 100000 ]]; then
        break
      else
        echo "Something is wrong; typescript.js got generated with a stupid size" >& /dev/stderr
        if [[ $n -eq 1 ]]; then
          exit 1
        fi

        rm -rf lib
        git reset --hard lib
      fi
    done

    cp -r lib/ "$BUILD_DIR"/
  fi

  echo "$BUILD_DIR"
}

rm -f "$PATCHFILE" && touch "$PATCHFILE"
rm -f "$JSPATCH" && touch "$JSPATCH"

while [[ ${#HASHES[@]} -gt 0 ]]; do
  BASE="${HASHES[0]}"
  PATCH="${HASHES[1]}"
  RANGE="${HASHES[2]}"
  HASHES=("${HASHES[@]:3}")

  make-build-for "$BASE"
  ORIG_DIR=$(build-dir-for "$BASE")

  make-build-for "$BASE" "$PATCH"
  PATCHED_DIR=$(build-dir-for "$BASE" "$PATCH")

  DIFF="$THIS_DIR"/patch."${PATCH}"-on-"${BASE}".diff

  git diff --no-index "$ORIG_DIR" "$PATCHED_DIR" \
    | perl -p -e"s#^--- #semver exclusivity $RANGE\n--- #" \
    | perl -p -e"s#$ORIG_DIR/#/#" \
    | perl -p -e"s#$PATCHED_DIR/#/#" \
    | perl -p -e"s#__spreadArrays#[].concat#" \
    > "$DIFF"

  cat "$DIFF" \
    >> "$PATCHFILE"
done

node "$THIS_DIR/../createPatch.js" "$PATCHFILE" "$JSPATCH"
