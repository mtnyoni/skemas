package main

import sdl "vendor:sdl2"
import img "vendor:sdl2/image"

Load_Texture :: proc(renderer: ^sdl.Renderer, path: cstring) -> (^sdl.Texture, bool) {
	texture := img.LoadTexture(renderer, path)
	if texture == nil {
		sdl.Log("Failed to load texture: %s", img.GetError())
		return nil, false
	}
	return texture, true
}
