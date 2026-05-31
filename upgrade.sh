#!/bin/bash
set -e

SPEC="skemas.spec"
SOURCE_DIR=$(rpm --eval '%{_sourcedir}')

# If a version argument is given, update the spec. Otherwise auto-increment Release.
if [ -n "$1" ]; then
    sed -i "s/^Version:.*/Version:        $1/" "$SPEC"
    sed -i "s/^Release:.*/Release:        1%{?dist}/" "$SPEC"
    echo "==> Version set to $1"
else
    CURRENT=$(grep '^Release:' "$SPEC" | grep -o '[0-9]\+')
    NEXT=$((CURRENT + 1))
    sed -i "s/^Release:.*/Release:        $NEXT%{?dist}/" "$SPEC"
    echo "==> Release bumped to $NEXT"
fi

echo "==> Building skemas..."
odin build . -collection:shared=vendor -o:speed

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
