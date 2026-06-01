package main

import "core:unicode/utf8"
import im "vendor/odin-imgui"

Icon :: enum u32 {
	ChevronDown       = 0xF000, // 61440
	ChevronRight      = 0xF001, // 61441
	Trash             = 0xF002, // 61442
	ArrowOnRectangle  = 0xF003, // 61443
	Link              = 0xF004, // 61444
	Db                = 0xF005, // 61445
	Table             = 0xF006, // 61446
	Lightning         = 0xF007, // 61447
	Idea              = 0xF008, // 61448
	LightMode         = 0xF009, // 61449
	Monitor           = 0xF00A, // 61450
	ExclamationCircle = 0xF00B, // 61451
	CheckCircle       = 0xF00C, // 61452
	Search            = 0xF00D, // 61453
	Key               = 0xF00E, // 61454
	Filter            = 0xF00F, // 61455
	Cog               = 0xF010, // 61456
	Eye               = 0xF011, // 61457
	EyeSlash          = 0xF012, // 61458
	Code              = 0xF013, // 61459
	Terminal          = 0xF014, // 61460
	File              = 0xF015, // 61461
	Bookmark          = 0xF016, // 61462
	Order             = 0xF017, // 61463
	Refresh           = 0xF018, // 61464
	Folder            = 0xF019, // 61465
	List              = 0xF01A, // 61466
	Bell              = 0xF01B, // 61467
	Moon              = 0xF01C, // 61468
	Plus              = 0xF01D, // 61469 - NEW!
}

// Encodes an Icon codepoint as a null-terminated UTF-8 cstring into buf.
// buf must be at least 5 bytes. Lifetime is tied to buf.
icon_str :: proc(icon: Icon, buf: ^[5]u8) -> cstring {
	bytes, n := utf8.encode_rune(rune(icon))
	copy(buf[:4], bytes[:n])
	buf[n] = 0
	return cstring(&buf[0])
}

// Render size for icons. The atlas is built at 16px for quality; we draw
// at this smaller size so the glyphs don't overpower the text beside them.
ICON_SIZE :: f32(14.0)

// Font handles
FONT_REGULAR_SM: ^im.Font
FONT_REGULAR: ^im.Font
FONT_MEDIUM_SM: ^im.Font
FONT_MEDIUM: ^im.Font
FONT_ICONS: ^im.Font

load_fonts :: proc(io: ^im.IO, dpi_scale: f32) {
	FONT_REGULAR = im.FontAtlas_AddFontFromFileTTF(
		io.Fonts,
		"fonts/Inter_18pt-Regular.ttf",
		16.0 * dpi_scale,
	)

	FONT_REGULAR_SM = im.FontAtlas_AddFontFromFileTTF(
		io.Fonts,
		"fonts/Inter_18pt-Regular.ttf",
		13.0 * dpi_scale,
	)

	FONT_MEDIUM_SM = im.FontAtlas_AddFontFromFileTTF(
		io.Fonts,
		"fonts/Inter_18pt-Medium.ttf",
		13.0 * dpi_scale,
	)

	FONT_MEDIUM = im.FontAtlas_AddFontFromFileTTF(
		io.Fonts,
		"fonts/Inter_18pt-Medium.ttf",
		16.0 * dpi_scale,
	)

	@(static) icon_ranges := [?]im.Wchar{0xF000, 0xF01D, 0}
	FONT_ICONS = im.FontAtlas_AddFontFromFileTTF(
		io.Fonts,
		"fonts/icons.ttf",
		16.0 * dpi_scale,
		nil,
		&icon_ranges[0],
	)
}
