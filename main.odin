package main

import "core:log"
import "core:mem"
import "core:thread"
import "core:time"
import im "vendor/odin-imgui"
import "vendor/odin-imgui/imgui_impl_sdl2"
import imgui_sql_renderer "vendor/odin-imgui/imgui_impl_sdlrenderer2"
import sqlite "vendor/odin-sqlite3"

import sdl "vendor:sdl2"

FONT_REGULAR_SM: ^im.Font
FONT_REGULAR: ^im.Font
FONT_MEDIUM_SM: ^im.Font
FONT_MEDIUM: ^im.Font


load_fonts :: proc(io: ^im.IO, dpi_scale: f32) {

	FONT_REGULAR = im.FontAtlas_AddFontFromFileTTF(
		io.Fonts,
		"fonts/Inter_18pt-Regular.ttf",
		16.0 * dpi_scale,
	)

	FONT_REGULAR_SM = im.FontAtlas_AddFontFromFileTTF(
		io.Fonts,
		"fonts/Inter_18pt-Regular.ttf",
		12.0 * dpi_scale,
	)

	FONT_MEDIUM_SM = im.FontAtlas_AddFontFromFileTTF(
		io.Fonts,
		"fonts/Inter_18pt-Medium.ttf",
		12.0 * dpi_scale,
	)

	FONT_MEDIUM = im.FontAtlas_AddFontFromFileTTF(
		io.Fonts,
		"fonts/Inter_18pt-Medium.ttf",
		16.0 * dpi_scale,
	)
}

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)
	defer mem.tracking_allocator_destroy(&track)

	assert(sdl.Init(sdl.INIT_EVERYTHING) == 0)
	defer sdl.Quit()

	window := sdl.CreateWindow(
		"Skemas",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		1280,
		720,
		{.RESIZABLE, .ALLOW_HIGHDPI},
	)
	assert(window != nil)
	defer sdl.DestroyWindow(window)

	renderer := sdl.CreateRenderer(window, -1, {.PRESENTVSYNC, .ACCELERATED})
	assert(renderer != nil)
	defer sdl.DestroyRenderer(renderer)

	im.CreateContext()
	defer im.DestroyContext()

	w, h: i32
	sdl.GetWindowSize(window, &w, &h)
	drawable_w, drawable_h: i32
	sdl.GetRendererOutputSize(renderer, &drawable_w, &drawable_h)

	dpi_scale := f32(drawable_w) / f32(w)

	io := im.GetIO()
	load_fonts(io, dpi_scale)

	io.ConfigFlags += {.DockingEnable}
	im.StyleColorsLight()
	style := im.GetStyle()
	im.Style_ScaleAllSizes(style, dpi_scale)

	imgui_impl_sdl2.InitForSDLRenderer(window, renderer)
	defer imgui_impl_sdl2.Shutdown()

	imgui_sql_renderer.Init(renderer)
	defer imgui_sql_renderer.Shutdown()

	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	running := true

	db, db_err := connect()
	if db_err != nil {
		log.errorf("%v", db_err)
		panic(db_err.(DB_OpenFailed).message)
	}
	defer sqlite.close(db)

	state := App_State {
		app_db = db,
		screen = .ConnectionScreen,
	}

	err := create_tables(db)
	if err != nil {
		log.errorf("%v", err)
		panic(err.(DB_ExecFailed).message)
	}

	// setup theme.
	colors := style.Colors
	colors[im.Col.WindowBg] = COLOR_BACKGROUND
	colors[im.Col.ChildBg] = COLOR_BACKGROUND
	colors[im.Col.PopupBg] = COLOR_BACKGROUND
	colors[im.Col.Text] = COLOR_FOREGROUND
	colors[im.Col.TextDisabled] = COLOR_MUTED_FOREGROUND
	colors[im.Col.Border] = COLOR_BORDER
	colors[im.Col.Separator] = COLOR_BORDER
	colors[im.Col.Header] = COLOR_MUTED_BACKGROUND
	colors[im.Col.HeaderHovered] = COLOR_MUTED_BACKGROUND
	colors[im.Col.HeaderActive] = COLOR_MUTED_BACKGROUND
	colors[im.Col.ScrollbarBg] = COLOR_BACKGROUND

	last_conn_check := time.tick_now()
	conn_check_interval :: 5 * time.Second
	health_checker: Conn_Health_Checker
	health_checker.status = .Connected
	health_thread: ^thread.Thread

	for running {
		e: sdl.Event

		for sdl.PollEvent(&e) {
			imgui_impl_sdl2.ProcessEvent(&e)

			#partial switch e.type {
			case .QUIT:
				running = false
			}
		}

		if pg_conn, ok := state.conn.(PQ_Conn); ok {
			state.conn_status = pg_conn_status(&health_checker)

			if time.tick_since(last_conn_check) >= conn_check_interval {
				last_conn_check = time.tick_now()
				if health_thread != nil {
					thread.join(health_thread)
					thread.destroy(health_thread)
				}

				health_thread = pg_spawn_health_check(&health_checker, pg_conn)
			}
		}

		imgui_sql_renderer.NewFrame()
		imgui_impl_sdl2.NewFrame()
		im.NewFrame()

		switch state.screen {
		case .ConnectionScreen:
			UIConnectDB(&state)

		case .DatabaseViewScreen:
			UIWorkspace(&state)
		}

		im.Render()

		sdl.SetRenderDrawColor(
			renderer,
			u8(COLOR_BACKGROUND.x * 255),
			u8(COLOR_BACKGROUND.y * 255),
			u8(COLOR_BACKGROUND.z * 255),
			255,
		)
		sdl.RenderClear(renderer)

		imgui_sql_renderer.RenderDrawData(im.GetDrawData(), renderer)
		sdl.RenderPresent(renderer)
	}
}
