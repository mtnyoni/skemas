package main

import im "vendor/odin-imgui"

FONT_SIZE_XS :: f32(14.0)
FONT_SIZE_SM :: f32(15.0)
FONT_SIZE_BASE :: f32(16.0)

// Font handles — one per typeface, size passed at push time via PushFontFloat
FONT_REGULAR: ^im.Font
FONT_MEDIUM: ^im.Font

load_fonts :: proc(io: ^im.IO) {
	FONT_REGULAR = im.FontAtlas_AddFontFromFileTTF(
		io.Fonts,
		"fonts/Inter_18pt-Regular.ttf",
		FONT_SIZE_BASE,
	)

	FONT_MEDIUM = im.FontAtlas_AddFontFromFileTTF(
		io.Fonts,
		"fonts/Inter_18pt-Medium.ttf",
		FONT_SIZE_BASE,
	)
}
