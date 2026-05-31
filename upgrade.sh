#!/bin/bash
set -e

SPEC="skemas.spec"
SOURCE_DIR=$(rpm --eval '%{_sourcedir}')

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
