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
	@(static) path_buf: [256]u8
	@(static) port: c.int = 5432
	@(static) db_type: Database_Type = .Postgres
	@(static) ssl_enabled: bool
	@(static) is_favorite: bool
	@(static) connections: []Connection
	@(static) loaded: bool
	@(static) is_to_save: bool
	@(static) conn_error: string
	@(static) pending_delete: Connection
	@(static) show_delete_dialog: bool
	@(static) pending_view: Connection
	@(static) show_view_dialog: bool

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
	im.Begin("Connections", nil, {.NoMove, .NoResize, .NoCollapse, .NoTitleBar})
	for conn in connections {
		cname := strings.clone_to_cstring(conn.name)
		defer delete(cname)

		if im.Selectable(cname) {
			cred, cred_err := get_credential(state.app_db, conn.credential_id)
			if cred_err == nil {
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
				switch conn.db_type {
				case .Postgres:
					pg_conn, conn_err := pg_connect(params)
					if conn_err == nil {
						state.conn = pg_conn
						state.db_needs_reload = true
						conn_error = ""
						state.screen = .DatabaseViewScreen
					} else {
						conn_error = conn_err.(DB_OpenFailed).message
						log.errorf("connect failed: %s", conn_error)
					}

				case .SQLite:
					sq_conn, conn_err := sqlite_connect(params)
					if conn_err == nil {
						state.conn = sq_conn
						state.db_needs_reload = true
						conn_error = ""
						state.screen = .DatabaseViewScreen
					} else {
						conn_error = conn_err.(DB_OpenFailed).message
						log.errorf("connect failed: %s", conn_error)
					}
				}
			}
		}

		ctx_id := strings.clone_to_cstring(
			strings.concatenate({"##ctx_", conn.id}, context.temp_allocator),
			context.temp_allocator,
		)
		if im.BeginPopupContextItem(ctx_id) {
			if im.MenuItem("View") {
				pending_view = conn
				show_view_dialog = true
			}

			if im.MenuItem("Delete") {
				pending_delete = conn
				show_delete_dialog = true
			}
			im.EndPopup()
		}
	}

	// Trigger modals after the loop — OpenPopup must sit in the same window scope as BeginPopupModal
	if show_view_dialog {
		im.OpenPopup("View Connection")
		show_view_dialog = false
	}

	if show_delete_dialog {
		im.OpenPopup("Delete Connection?")
		show_delete_dialog = false
	}

	// ── View modal ────────────────────────────────────────────────────────────
	if im.BeginPopupModal("View Connection", nil, {.AlwaysAutoResize}) {
		name_c := strings.clone_to_cstring(pending_view.name)
		defer delete(name_c)
		host_c := strings.clone_to_cstring(pending_view.host)
		defer delete(host_c)
		user_c := strings.clone_to_cstring(pending_view.username)
		defer delete(user_c)
		im.Text("Name:"); im.SameLine(); im.Text(name_c)
		im.Text("Type:"); im.SameLine()
		im.Text("postgres" if pending_view.db_type == .Postgres else "sqlite")
		if pending_view.db_type == .Postgres {
			im.Text("Host:"); im.SameLine(); im.Text(host_c)
			im.Text("Username:"); im.SameLine(); im.Text(user_c)
		} else {
			im.Text("Path:"); im.SameLine(); im.Text(host_c)
		}
		im.Spacing()
		im.Separator()
		im.Spacing()
		if im.Button("Close", {-1, 0}) {
			im.CloseCurrentPopup()
		}
		im.EndPopup()
	}

	Delete_Dialog(
		{
			loaded = &loaded,
			pending_delete = &pending_delete,
			state = state,
			conn_error = &conn_error,
		},
	)
	im.End()

	center_x := sidebar_w + (display.x - sidebar_w) * 0.5
	im.SetNextWindowPos({center_x, display.y * 0.5}, .Always, {0.5, 0.5})
	im.SetNextWindowSize({400, 0}, .Always)

	im.PushStyleVar(.WindowRounding, 8.0)
	im.PushStyleVar(.WindowBorderSize, 1.0)
	im.PushStyleVarImVec2(.WindowPadding, {20, 20})
	im.PushStyleColor(.Border, im.GetColorU32(.Border))

	im.Begin("New Connection", nil, {.NoMove, .NoResize, .NoCollapse, .NoTitleBar})
	defer im.End()

	im.PopStyleColor(1)
	im.PopStyleVar(3)

	im.PushStyleVar(.FrameRounding, 4.0)
	im.PushStyleVar(.GrabRounding, 4.0)
	im.PushStyleVar(.FrameBorderSize, 1.0)
	im.PushStyleColorImVec4(.FrameBg, {1.00, 1.00, 1.00, 1.00})
	im.PushStyleColorImVec4(.FrameBgHovered, {0.94, 0.96, 1.00, 1.00})
	im.PushStyleColorImVec4(.FrameBgActive, {0.88, 0.92, 1.00, 1.00})
	im.PushStyleColorImVec4(.Border, {0.72, 0.75, 0.82, 1.00})
	defer im.PopStyleVar(3)
	defer im.PopStyleColor(4)

	im.Text("Name")
	im.SetNextItemWidth(-1)
	im.InputText("##name", cast(cstring)&name_buf[0], len(name_buf))

	im.Spacing()
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

	#partial switch db_type {
	case .SQLite:
		im.Spacing()
		im.Text("Path")
		browse_lbl: cstring = "Browse..."
		style := im.GetStyle()
		browse_w := im.CalcTextSize(browse_lbl).x + style.FramePadding.x * 2 + style.ItemSpacing.x
		im.SetNextItemWidth(-browse_w)
		im.InputText("##path", cast(cstring)&path_buf[0], len(path_buf))
		im.SameLine()

		if im.Button(browse_lbl) {
			path := pick_file("Select SQLite Database")
			if path != "" {
				n := min(len(path), len(path_buf) - 1)
				copy(path_buf[:n], transmute([]u8)path[:n])
				path_buf[n] = 0
			}
		}

	case .Postgres:
		im.Spacing()
		im.Text("Host")
		im.SetNextItemWidth(-1)
		im.InputText("##host", cast(cstring)&host_buf[0], len(host_buf))

		im.Spacing()
		im.Text("Port")
		im.SetNextItemWidth(-1)
		im.InputInt("##port", &port, 0, 0)

		im.Spacing()
		im.Text("Username")
		im.SetNextItemWidth(-1)
		im.InputText("##username", cast(cstring)&username_buf[0], len(username_buf))

		im.Spacing()
		im.Text("Password")
		im.SetNextItemWidth(-1)
		im.InputText("##password", cast(cstring)&password_buf[0], len(password_buf), {.Password})

		im.Spacing()
		im.Checkbox("SSL Enabled", &ssl_enabled)
	}

	im.Checkbox("Favorite", &is_favorite)
	im.Checkbox("Save DB", &is_to_save)
	if conn_error != "" {
		cerr := strings.clone_to_cstring(conn_error)
		defer delete(cerr)
		im.TextColored({1, 0.3, 0.3, 1}, cerr)
	}
	im.Spacing()
	im.Separator()
	im.Spacing()

	if im.Button("Connect", {-1, 0}) {
		new_conn := Db_New_Connection {
			creds = &New_Credential {
				auth_type = "password",
				secret_key = strings.clone_from(cast(cstring)&password_buf[0]),
			},
			conn  = &New_Connection {
				name = strings.clone_from(cast(cstring)&name_buf[0]),
				db_type = db_type,
				host = strings.clone_from(
					cast(cstring)(&path_buf[0] if db_type == .SQLite else &host_buf[0]),
				),
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

		#partial switch db_type {
		case .Postgres:
			pg_conn, conn_err := pg_connect(new_conn)

			if conn_err == nil {
				state.conn = pg_conn
				conn_error = ""
				loaded = false
				state.db_needs_reload = true
				state.screen = .DatabaseViewScreen

			} else {
				conn_error = conn_err.(DB_OpenFailed).message
				log.errorf("connect failed: %s", conn_error)
			}
		case .SQLite:
			sq_conn, conn_err := sqlite_connect(new_conn)
			if conn_err == nil {
				state.conn = sq_conn
				conn_error = ""
				loaded = false
				state.db_needs_reload = true
				state.screen = .DatabaseViewScreen
			} else {
				conn_error = conn_err.(DB_OpenFailed).message
				log.errorf("connect failed: %s", conn_error)
			}
		}
	}
}

Delete_DialogProps :: struct {
	loaded:         ^bool,
	pending_delete: ^Connection,
	state:          ^App_State,
	conn_error:     ^string,
}

Delete_Dialog :: proc(props: Delete_DialogProps) {
	im.Spacing()
	im.PushStyleVar(.WindowRounding, 8.0)
	im.PushStyleVar(.WindowBorderSize, 1.0)
	im.PushStyleVarImVec2(.WindowPadding, {15, 15})
	im.PushStyleColorImVec4(.Border, {0.64, 0.68, 0.75, 1.0})
	if im.BeginPopupModal("Delete Connection?", nil, {.AlwaysAutoResize, .NoTitleBar}) {

		del_name_c := strings.clone_to_cstring(props.pending_delete.name)
		defer delete(del_name_c)
		im.PushFont(font_medium)
		im.Text("Delete connection?")
		im.PopFont()

		im.TextColored({0.64, 0.68, 0.75, 1.0}, "This cannot be undone.")

		im.Spacing()
		im.Separator()
		im.Spacing()

		im.PushStyleVar(.FrameRounding, 4.0)
		im.PushStyleVar(.GrabRounding, 4.0)
		im.PushStyleVar(.FrameBorderSize, 1.0)
		if im.Button("Delete", {120, 0}) {
			err := delete_connection(
				props.state.app_db,
				props.pending_delete.id,
				props.pending_delete.credential_id,
			)
			if err == nil {
				props.loaded^ = false
			} else {
				props.conn_error^ = "Failed to delete connection"
			}
			im.CloseCurrentPopup()
		}
		im.SameLine()
		if im.Button("Cancel", {120, 0}) {
			im.CloseCurrentPopup()
		}

		im.PopStyleVar(3)
		im.EndPopup()
	}
	im.PopStyleColor(1)
	im.PopStyleVar(3)
}
