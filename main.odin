package main

import im "vendor/odin-imgui"
import "vendor/odin-imgui/imgui_impl_sdl2"
import "vendor/odin-imgui/imgui_impl_sdlrenderer2"

import sdl "vendor:sdl2"

hit_test :: proc "c" (win: ^sdl.Window, area: ^sdl.Point, data: rawptr) -> sdl.HitTestResult {
	w, h: i32
	sdl.GetWindowSize(win, &w, &h)

	border := i32(4)
	if area.y < border {
		if area.x < border { return .RESIZE_TOPLEFT }
		if area.x > w - border { return .RESIZE_TOPRIGHT }
		return .RESIZE_TOP
	}
	if area.y > h - border {
		if area.x < border { return .RESIZE_BOTTOMLEFT }
		if area.x > w - border { return .RESIZE_BOTTOMRIGHT }
		return .RESIZE_BOTTOM
	}
	if area.x < border { return .RESIZE_LEFT }
	if area.x > w - border { return .RESIZE_RIGHT }

	if area.y < 30 {
		if area.x < w - 120 {
			return .DRAGGABLE
		}
	}

	return .NORMAL
}

main :: proc() {
	assert(sdl.Init(sdl.INIT_EVERYTHING) == 0)
	defer sdl.Quit()

	window := sdl.CreateWindow(
		"Custom Title Bar",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		1280,
		720,
		{.RESIZABLE, .ALLOW_HIGHDPI, .BORDERLESS},
	)
	assert(window != nil)
	defer sdl.DestroyWindow(window)

	sdl.SetWindowHitTest(window, hit_test, nil)

	renderer := sdl.CreateRenderer(window, -1, {.PRESENTVSYNC, .ACCELERATED})
	assert(renderer != nil)
	defer sdl.DestroyRenderer(renderer)

	im.CreateContext()
	defer im.DestroyContext()

	io := im.GetIO()
	io.ConfigFlags += {.DockingEnable}

	imgui_impl_sdl2.InitForSDLRenderer(window, renderer)
	defer imgui_impl_sdl2.Shutdown()

	imgui_impl_sdlrenderer2.Init(renderer)
	defer imgui_impl_sdlrenderer2.Shutdown()

	running := true
	want_maximize := false
	want_minimize := false

	for running {
		e: sdl.Event

		for sdl.PollEvent(&e) {
			imgui_impl_sdl2.ProcessEvent(&e)

			#partial switch e.type {
			case .QUIT:
				running = false

			case .KEYDOWN:
				if e.key.keysym.sym == .F11 {
					want_maximize = true
				}

				if e.key.keysym.mod & sdl.KMOD_GUI != {} {
					#partial switch e.key.keysym.sym {
					case .UP:
						want_maximize = true
					case .DOWN:
						want_minimize = true
					}
				}
			}
		}

		// -------- Window state --------
		window_w, window_h: i32
		sdl.GetWindowSize(window, &window_w, &window_h)

		flags := sdl.GetWindowFlags(window)
		is_maximized := (flags & {.MAXIMIZED}) != {}

		if want_maximize {
			if is_maximized {
				sdl.RestoreWindow(window)
			} else {
				sdl.MaximizeWindow(window)
			}
			want_maximize = false
		}

		if want_minimize {
			sdl.MinimizeWindow(window)
			want_minimize = false
		}

		// -------- ImGui --------
		imgui_impl_sdlrenderer2.NewFrame()
		imgui_impl_sdl2.NewFrame()
		im.NewFrame()

		// Dockspace first (as background)
		im.DockSpaceOverViewport()

		// Title bar (on top)
		im.SetNextWindowPos({0, 0})
		im.SetNextWindowSize({f32(window_w), 30})

		flags_window := im.WindowFlags{
			.NoTitleBar,
			.NoResize,
			.NoMove,
			.NoScrollbar,
		}

		im.PushStyleVar(im.StyleVar.WindowBorderSize, 0)

		if im.Begin("##titlebar", nil, flags_window) {
			im.Text("My App")

			im.SameLine()

			// Align buttons to the right
			button_count :: 3
			button_w     :: 30
			im.SetCursorPosX(f32(window_w) - (button_w + 8) * button_count)

			if im.Button("_", {button_w, 0}) {
				want_minimize = true
			}

			im.SameLine()

			if im.Button(is_maximized ? "R" : "M", {button_w, 0}) {
				want_maximize = true
			}

			im.SameLine()

			im.PushStyleColor(im.Col.Button, im.GetColorU32ImVec4(im.Vec4{0.8, 0.2, 0.2, 1}))
			if im.Button("X", {button_w, 0}) {
				running = false
			}
			im.PopStyleColor(1)
		}
		im.End()

		im.PopStyleVar(1)

		im.ShowDemoWindow()

		im.Render()

		sdl.SetRenderDrawColor(renderer, 20, 20, 30, 255)
		sdl.RenderClear(renderer)

		imgui_impl_sdlrenderer2.RenderDrawData(im.GetDrawData(), renderer)
		sdl.RenderPresent(renderer)
	}
}
