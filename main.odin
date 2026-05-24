package main

import "core:log"
import im "vendor/odin-imgui"
import "vendor/odin-imgui/imgui_impl_sdl2"
import imgui_sql_renderer "vendor/odin-imgui/imgui_impl_sdlrenderer2"
import sqlite "vendor/odin-sqlite3"

import sdl "vendor:sdl2"

main :: proc() {
	assert(sdl.Init(sdl.INIT_EVERYTHING) == 0)
	defer sdl.Quit()

	window := sdl.CreateWindow(
		"My App",
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

	io := im.GetIO()
	io.ConfigFlags += {.DockingEnable}

	imgui_impl_sdl2.InitForSDLRenderer(window, renderer)
	defer imgui_impl_sdl2.Shutdown()

	imgui_sql_renderer.Init(renderer)
	defer imgui_sql_renderer.Shutdown()

	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	running := true

	db, db_err := connect()
	if db_err != .Ok {
		log.errorf("failed to open database: %v", db_err)
		return
	}
	defer sqlite.close(db)
	create_tables(db)
	log.info("tables created")

	new_db_conn := Db_New_Connection {
		credential = &New_Credential{auth_type = "password", secret_key = "root"},
		conn       = &New_Connection {
			name = "postgres-local",
			db_type = "postgres",
			host = "localhost",
			port = 5432,
			database_name = "postgres",
			username = "postgres",
			ssl_enabled = true,
			is_favorite = false,
		},
	}

	save_db_connection(db, &new_db_conn)

	conns := get_connections(db)
	log.info("connections", len(conns))

	for running {
		e: sdl.Event

		for sdl.PollEvent(&e) {
			imgui_impl_sdl2.ProcessEvent(&e)

			#partial switch e.type {
			case .QUIT:
				running = false
			}
		}

		imgui_sql_renderer.NewFrame()
		imgui_impl_sdl2.NewFrame()
		im.NewFrame()

		im.DockSpaceOverViewport()
		im.ShowDemoWindow()
		im.Render()

		sdl.SetRenderDrawColor(renderer, 20, 20, 30, 255)
		sdl.RenderClear(renderer)

		imgui_sql_renderer.RenderDrawData(im.GetDrawData(), renderer)
		sdl.RenderPresent(renderer)
	}
}
