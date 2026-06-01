#!/bin/bash
set -e

SPEC="skemas.spec"
SOURCE_DIR=$(rpm --eval '%{_sourcedir}')

# Resolve version: explicit arg > latest git tag > keep current
if [ -n "$1" ]; then
    VERSION="$1"
    sed -i "s/^Version:.*/Version:        $VERSION/" "$SPEC"
    sed -i "s/^Release:.*/Release:        1%{?dist}/" "$SPEC"
    echo "==> Version set to $VERSION"
elif git_tag=$(git describe --tags --abbrev=0 2>/dev/null); then
    VERSION="${git_tag#v}"  # strip leading 'v' if present
    SPEC_VER=$(grep '^Version:' "$SPEC" | awk '{print $2}')
    if [ "$VERSION" != "$SPEC_VER" ]; then
        sed -i "s/^Version:.*/Version:        $VERSION/" "$SPEC"
        sed -i "s/^Release:.*/Release:        1%{?dist}/" "$SPEC"
        echo "==> Version set from git tag: $VERSION"
    else
        CURRENT=$(grep '^Release:' "$SPEC" | grep -o '[0-9]\+')
        NEXT=$((CURRENT + 1))
        sed -i "s/^Release:.*/Release:        $NEXT%{?dist}/" "$SPEC"
        echo "==> Release bumped to $NEXT (version $VERSION)"
    fi
else
    CURRENT=$(grep '^Release:' "$SPEC" | grep -o '[0-9]\+')
    NEXT=$((CURRENT + 1))
    sed -i "s/^Release:.*/Release:        $NEXT%{?dist}/" "$SPEC"
    echo "==> Release bumped to $NEXT"
fi

VERSION=$(grep '^Version:' "$SPEC" | awk '{print $2}')

echo "==> Building skemas $VERSION..."
odin build . -collection:shared=vendor -o:speed -define:APP_VERSION="$VERSION"

echo "==> Copying sources to $SOURCE_DIR..."
cp skemas                          "$SOURCE_DIR/skemas"
cp fonts/Inter_18pt-Regular.ttf    "$SOURCE_DIR/"
cp fonts/Inter_18pt-Medium.ttf     "$SOURCE_DIR/"
cp fonts/icons.ttf                 "$SOURCE_DIR/"
cp assets/s.png                    "$SOURCE_DIR/"
cp skemas.desktop                  "$SOURCE_DIR/skemas.desktop"

echo "==> Building RPM..."
rpmbuild -bb "$SPEC"

RPM=$(rpm --eval '%{_rpmdir}')/x86_64/skemas-*.rpm
echo "==> Upgrading package..."
sudo rpm -U --force $RPM

echo "==> Done."
