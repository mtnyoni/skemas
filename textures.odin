package main

import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

Load_Texture :: proc(renderer: ^sdl.Renderer, path: cstring) -> (^sdl.Texture, bool) {
	texture := img.LoadTexture(renderer, path)
	if texture == nil {
		return nil, false
	}
	return texture, true
}
