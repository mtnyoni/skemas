package main

import im "vendor/odin-imgui"

ICON_ANGLE_DOWN :: "\xef\x84\x87"
ICON_PLUS :: "\xe2\xa0\x80"
ICON_ANGLE_RIGHT :: "\xef\x84\x85"

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

	@(static) icon_ranges := [5]im.Wchar{59392, 59392, 61701, 61703, 0}
	FONT_ICONS = im.FontAtlas_AddFontFromFileTTF(
		io.Fonts,
		"fonts/icons.ttf",
		16.0 * dpi_scale,
		nil,
		&icon_ranges[0],
	)
}
