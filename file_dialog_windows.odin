//+build windows
package main

import "core:sys/windows"

OFN_FILEMUSTEXIST :: u32(0x00001000)
OFN_PATHMUSTEXIST :: u32(0x00000800)

// OPENFILENAME is not in core:sys/windows so we define it here.
OPENFILENAMEW :: struct {
	lStructSize:       u32,
	hwndOwner:         windows.HWND,
	hInstance:         windows.HINSTANCE,
	lpstrFilter:       windows.LPCWSTR,
	lpstrCustomFilter: windows.LPWSTR,
	nMaxCustFilter:    u32,
	nFilterIndex:      u32,
	lpstrFile:         windows.LPWSTR,
	nMaxFile:          u32,
	lpstrFileTitle:    windows.LPWSTR,
	nMaxFileTitle:     u32,
	lpstrInitialDir:   windows.LPCWSTR,
	lpstrTitle:        windows.LPCWSTR,
	Flags:             u32,
	nFileOffset:       u16,
	nFileExtension:    u16,
	lpstrDefExt:       windows.LPCWSTR,
	lCustData:         windows.LPARAM,
	lpfnHook:          rawptr,
	lpTemplateName:    windows.LPCWSTR,
	pvReserved:        rawptr,
	dwReserved:        u32,
	FlagsEx:           u32,
}

foreign import comdlg32 "system:Comdlg32.lib"
@(default_calling_convention = "stdcall")
foreign comdlg32 {
	GetOpenFileNameW :: proc(lpofn: ^OPENFILENAMEW) -> windows.BOOL ---
}

pick_file :: proc(title := "Select File") -> string {
	buf: [260]u16
	title_wide := windows.utf8_to_wstring(title)

	ofn := OPENFILENAMEW{
		lStructSize = size_of(OPENFILENAMEW),
		lpstrFile   = &buf[0],
		nMaxFile    = 260,
		lpstrTitle  = title_wide,
		Flags       = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST,
	}

	if GetOpenFileNameW(&ofn) == 0 {return ""}

	path, _ := windows.wstring_to_utf8(&buf[0], -1)
	return path
}
