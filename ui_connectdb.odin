package main

import "core:c"
import "core:log"
import "core:strings"
import im "vendor/odin-imgui"

UIConnectDB :: proc(state: ^App_State) {
	@(static) name_buf: [256]u8
	@(static) host_buf: [256]u8
	@(static) username_buf: [256]u8
	@(static) password_buf: [256]u8
	@(static) port: c.int = 5432
	@(static) db_type: Database_Type = .Postgres
	@(static) ssl_enabled: bool
	@(static) is_favorite: bool
	@(static) connections: []Connection
	@(static) loaded: bool
	@(static) is_to_save: bool
	@(static) conn_error: string

	if !loaded {
		conns, err := get_connections(state.app_db)
		if err == nil {
			connections = conns
		}
		loaded = true
	}

	db_type_labels := [Database_Type]cstring {
		.Postgres = "postgres",
		.SQLite   = "sqlite",
	}

	display := im.GetIO().DisplaySize
	sidebar_w: f32 = 260

	// Sidebar
	im.SetNextWindowPos({0, 0}, .Always)
	im.SetNextWindowSize({sidebar_w, display.y}, .Always)
	im.Begin("Connections", nil, {.NoMove, .NoResize, .NoCollapse})
	for conn in connections {
		cname := strings.clone_to_cstring(conn.name)
		defer delete(cname)
		if im.Selectable(cname) {
			cred, cred_err := get_credential(state.app_db, conn.credential_id)

			if cred_err == nil && conn.db_type == .Postgres {
				new_cred := New_Credential {
					auth_type  = cred.auth_type,
					secret_key = cred.secret_key,
				}

				new_conn_data := New_Connection {
					name        = conn.name,
					db_type     = conn.db_type,
					host        = conn.host,
					port        = conn.port,
					username    = conn.username,
					ssl_enabled = conn.sql_enabled,
				}

				params := Db_New_Connection {
					creds = &new_cred,
					conn  = &new_conn_data,
				}

				pg_conn, conn_err := pg_connect(params)
				if conn_err == nil {
					state.conn = pg_conn
					state.needs_db_reload = true
					conn_error = ""
					state.screen = .DatabaseViewScreen

				} else {
					conn_error = conn_err.(DB_Open_Failed).message
					log.errorf("connect failed: %s", conn_error)
				}
			}
		}
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


	im.Text("Username")
	im.SetNextItemWidth(-1)
	im.InputText("##username", cast(cstring)&username_buf[0], len(username_buf))

	im.Text("Password")
	im.SetNextItemWidth(-1)
	im.InputText("##password", cast(cstring)&password_buf[0], len(password_buf), {.Password})

	im.Checkbox("SSL Enabled", &ssl_enabled)
	im.Checkbox("Favorite", &is_favorite)
	im.Checkbox("Save DB", &is_to_save)
	if conn_error != "" {
		cerr := strings.clone_to_cstring(conn_error)
		defer delete(cerr)
		im.TextColored({1, 0.3, 0.3, 1}, cerr)
	}
	im.Separator()

	if im.Button("Connect", {-1, 0}) {
		new_conn := Db_New_Connection {
			creds = &New_Credential {
				auth_type = "password",
				secret_key = strings.clone_from(cast(cstring)&password_buf[0]),
			},
			conn  = &New_Connection {
				name = strings.clone_from(cast(cstring)&name_buf[0]),
				db_type = db_type,
				host = strings.clone_from(cast(cstring)&host_buf[0]),
				port = int(port),
				username = strings.clone_from(cast(cstring)&username_buf[0]),
				ssl_enabled = ssl_enabled,
				is_favorite = is_favorite,
			},
		}

		if is_to_save {
			err := save_db_connection(state.app_db, &new_conn)
			if err != nil {
				im.OpenPopup("Error")
			}
		}

		if new_conn.conn.db_type == .Postgres {
			pg_conn, conn_err := pg_connect(new_conn)
			if conn_err == nil {
				state.conn = pg_conn
				conn_error = ""
				loaded = false
				state.needs_db_reload = true
				state.screen = .DatabaseViewScreen
			} else {
				conn_error = conn_err.(DB_Open_Failed).message
				log.errorf("connect failed: %s", conn_error)
			}
		}
	}
}
