Name:           skemas
Version:        0.2.1
Release:        1%{?dist}
Summary:        Database client
License:        MIT
BuildArch:      x86_64

Source0:        skemas
Source1:        skemas.desktop
Source2:        Inter_18pt-Regular.ttf
Source3:        Inter_18pt-Medium.ttf
Source4:        icons.ttf
Source5:        s.png

Requires:       sdl2-compat
Requires:       SDL2_image
Requires:       sqlite-libs

%description
Skemas is a database client.

%install
rm -rf %{buildroot}

install -Dm755 %{SOURCE0}  %{buildroot}/usr/share/skemas/skemas
install -Dm644 %{SOURCE1}  %{buildroot}/usr/share/applications/skemas.desktop
install -Dm644 %{SOURCE2}  %{buildroot}/usr/share/skemas/fonts/Inter_18pt-Regular.ttf
install -Dm644 %{SOURCE3}  %{buildroot}/usr/share/skemas/fonts/Inter_18pt-Medium.ttf
install -Dm644 %{SOURCE4}  %{buildroot}/usr/share/skemas/fonts/icons.ttf
install -Dm644 %{SOURCE5}  %{buildroot}/usr/share/skemas/assets/s.png
install -Dm644 %{SOURCE5}  %{buildroot}/usr/share/pixmaps/skemas.png

mkdir -p %{buildroot}/usr/local/bin
printf '#!/bin/bash\ncd /usr/share/skemas\nexec ./skemas "$@"\n' \
    > %{buildroot}/usr/local/bin/skemas
chmod 755 %{buildroot}/usr/local/bin/skemas

%files
/usr/share/skemas/skemas
/usr/share/skemas/fonts/Inter_18pt-Regular.ttf
/usr/share/skemas/fonts/Inter_18pt-Medium.ttf
/usr/share/skemas/fonts/icons.ttf
/usr/share/skemas/assets/s.png
/usr/share/applications/skemas.desktop
/usr/share/pixmaps/skemas.png
/usr/local/bin/skemas

%changelog
* Sun May 31 2026 Tawanda M Nyoni <nyonitawandam@gmail.com> - 0.1.0-1
- Initial build
