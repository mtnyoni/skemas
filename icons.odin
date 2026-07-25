package main

import "core:fmt"
import "core:strings"
import im "vendor/odin-imgui"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

ICON_SIZE :: f32(14.0)

ICON_FUNNEL :: "assets/icons/png/funnel.png"
ICON_PLUS :: "assets/icons/png/plus.png"
ICON_BELL :: "assets/icons/png/bell.png"
ICON_BELL_SLASH :: "assets/icons/png/bell-slash.png"
ICON_CHEVRON_DOWN :: "assets/icons/png/chevron-down.png"
ICON_CHEVRON_UP :: "assets/icons/png/chevron-up.png"
ICON_CHEVRON_RIGHT :: "assets/icons/png/chevron-right.png"
ICON_CHEVRON_LEFT :: "assets/icons/png/chevron-left.png"
ICON_ARROW_PATH :: "assets/icons/png/arrow-path.png"

ICON_PATHS :: [?]string {
	ICON_FUNNEL,
	ICON_PLUS,
	ICON_BELL,
	ICON_BELL_SLASH,
	ICON_CHEVRON_DOWN,
	ICON_CHEVRON_UP,
	ICON_CHEVRON_RIGHT,
	ICON_CHEVRON_LEFT,
	ICON_ARROW_PATH,
}

icon_renderer: ^sdl.Renderer
icon_textures: map[string]^sdl.Texture

init_icon_textures :: proc(renderer: ^sdl.Renderer) -> bool {
	if renderer == nil || icon_renderer != nil {
		return false
	}

	icon_renderer = renderer
	icon_textures = make(map[string]^sdl.Texture)

	for path in ICON_PATHS {
		if _, ok := load_icon_texture(path); !ok {
			fmt.eprintf("Failed to load icon texture %q: %s\n", path, sdl.GetError())
			destroy_icon_textures()
			return false
		}
	}

	return true
}

load_icon_texture :: proc(path: string) -> (texture: ^sdl.Texture, ok: bool) {
	if icon_renderer == nil {
		return nil, false
	}

	if cached, found := icon_textures[path]; found {
		return cached, true
	}

	c_path, alloc_err := strings.clone_to_cstring(path)
	if alloc_err != nil {
		return nil, false
	}
	defer delete(c_path)

	texture = img.LoadTexture(icon_renderer, c_path)
	if texture == nil {
		return nil, false
	}
	sdl.SetTextureScaleMode(texture, .LINEAR)

	owned_path, path_alloc_err := strings.clone(path)
	if path_alloc_err != nil {
		sdl.DestroyTexture(texture)
		return nil, false
	}

	icon_textures[owned_path] = texture
	return texture, true
}

draw_icon :: proc(
	draw_list: ^im.DrawList,
	path: string,
	pos: im.Vec2,
	size: f32,
	color: u32,
) -> bool {
	texture, ok := load_icon_texture(path)
	if !ok {
		return false
	}

	texture_ref := im.TextureRef {
		_TexID = cast(im.TextureID)cast(uintptr)texture,
	}
	im.DrawList_AddImage(
		draw_list,
		texture_ref,
		pos,
		{pos.x + size, pos.y + size},
		{0, 0},
		{1, 1},
		color,
	)
	return true
}

destroy_icon_textures :: proc() {
	if icon_textures != nil {
		for path, texture in icon_textures {
			sdl.DestroyTexture(texture)
			delete(path)
		}
		delete(icon_textures)
	}

	icon_textures = nil
	icon_renderer = nil
}
