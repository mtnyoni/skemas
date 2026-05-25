package main

import "core:c"
import "core:strings"
import im "vendor/odin-imgui"

Connection_Screen :: proc(state: ^App_State) {
	@(static) name_buf:    [256]u8
	@(static) host_buf:    [256]u8
	@(static) db_name_buf: [256]u8
	@(static) username_buf:[256]u8
	@(static) password_buf:[256]u8
	@(static) port:        c.int = 5432
	@(static) db_type:     Database_Type = .Postgres
	@(static) ssl_enabled: bool
	@(static) is_favorite: bool
	@(static) connections: []Connection
	@(static) loaded:      bool

	if !loaded {
		conns, err := get_connections(state.db)
		if err == nil {
			connections = conns
		}
		loaded = true
	}

	db_type_labels := [Database_Type]cstring {
		.Postgres = "postgres",
		.SQLite   = "sqlite",
	}

	display      := im.GetIO().DisplaySize
	sidebar_w: f32 = 260

	// Sidebar
	im.SetNextWindowPos({0, 0}, .Always)
	im.SetNextWindowSize({sidebar_w, display.y}, .Always)
	im.Begin("Connections", nil, {.NoMove, .NoResize, .NoCollapse})
	for conn in connections {
		cname := strings.clone_to_cstring(conn.name)
		defer delete(cname)
		im.Selectable(cname)
	}
	im.End()

	// Form — centered in the space to the right of the sidebar
	center_x := sidebar_w + (display.x - sidebar_w) * 0.5
	im.SetNextWindowPos({center_x, display.y * 0.5}, .Always, {0.5, 0.5})
	im.SetNextWindowSize({400, 0}, .Always)
	im.Begin("New Connection", nil, {.NoMove, .NoResize, .NoCollapse})
	defer im.End()

	im.Text("Name")
	im.SetNextItemWidth(-1)
	im.InputText("##name", cast(cstring)&name_buf[0], len(name_buf))

	im.Text("Database Type")
	im.SetNextItemWidth(-1)
	if im.BeginCombo("##db_type", db_type_labels[db_type]) {
		for label, t in db_type_labels {
			if im.Selectable(label, db_type == t) {
				db_type = t
			}
		}
		im.EndCombo()
	}

	im.Text("Host")
	im.SetNextItemWidth(-1)
	im.InputText("##host", cast(cstring)&host_buf[0], len(host_buf))

	im.Text("Port")
	im.SetNextItemWidth(-1)
	im.InputInt("##port", &port)

	im.Text("Database Name")
	im.SetNextItemWidth(-1)
	im.InputText("##database_name", cast(cstring)&db_name_buf[0], len(db_name_buf))

	im.Text("Username")
	im.SetNextItemWidth(-1)
	im.InputText("##username", cast(cstring)&username_buf[0], len(username_buf))

	im.Text("Password")
	im.SetNextItemWidth(-1)
	im.InputText("##password", cast(cstring)&password_buf[0], len(password_buf), {.Password})

	im.Checkbox("SSL Enabled", &ssl_enabled)
	im.Checkbox("Favorite", &is_favorite)
	im.Separator()

	if im.Button("Connect", {-1, 0}) {
		new_conn := Db_New_Connection {
			credential = &New_Credential {
				auth_type  = "password",
				secret_key = strings.clone_from(cast(cstring)&password_buf[0]),
			},
			conn       = &New_Connection {
				name          = strings.clone_from(cast(cstring)&name_buf[0]),
				db_type       = db_type,
				host          = strings.clone_from(cast(cstring)&host_buf[0]),
				port          = int(port),
				database_name = strings.clone_from(cast(cstring)&db_name_buf[0]),
				username      = strings.clone_from(cast(cstring)&username_buf[0]),
				ssl_enabled   = ssl_enabled,
				is_favorite   = is_favorite,
			},
		}

		err := save_db_connection(state.db, &new_conn)
		if err == nil {
			loaded = false
			state.screen = .DatabaseViewScreen
		}
	}
}
