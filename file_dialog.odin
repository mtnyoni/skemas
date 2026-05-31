//+build linux, darwin
package main

import "core:c"
import "core:strings"

foreign import libc "system:c"

@(default_calling_convention = "c")
foreign libc {
	@(link_name = "popen") _popen :: proc(command, mode: cstring) -> rawptr ---
	@(link_name = "pclose") _pclose :: proc(stream: rawptr) -> c.int ---
	@(link_name = "fgets") _fgets :: proc(s: [^]u8, n: c.int, stream: rawptr) -> [^]u8 ---
}

// Opens the OS native file picker and returns the chosen path.
// Blocks until the dialog is closed. Returns "" if cancelled or unavailable.
pick_file :: proc(title := "Select File") -> string {
	cmd := strings.clone_to_cstring(
		strings.concatenate(
			{
				"zenity --file-selection --title='",
				title,
				"' 2>/dev/null || kdialog --getopenfilename . 2>/dev/null",
			},
			context.temp_allocator,
		),
		context.temp_allocator,
	)

	pipe := _popen(cmd, "r")
	if pipe == nil {return ""}
	defer _pclose(pipe)

	buf: [4096]u8
	if _fgets(&buf[0], c.int(len(buf)), pipe) == nil {return ""}

	return strings.clone(strings.trim_right(string(cstring(&buf[0])), "\r\n"))
}
