package main

import "core:c"
import "core:fmt"
import "core:log"
import "core:strings"
import im "vendor/odin-imgui"

SIDEBAR_WIDTH: f32 = 260

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

	displaySize := im.GetIO().DisplaySize
	fbScale := im.GetIO().DisplayFramebufferScale

	im.SetNextWindowPos({0, 0}, .Always)
	im.SetNextWindowSize({SIDEBAR_WIDTH, displaySize.y * fbScale.y}, .Always)
	im.PushStyleColorImVec4(.WindowBg, COLOR_BACKGROUND)
	defer im.PopStyleColor()
	im.Begin("Connections", nil, {.NoMove, .NoResize, .NoCollapse, .NoTitleBar, .NoScrollbar})
	for conn in connections {
		cname := strings.clone_to_cstring(conn.name)
		defer delete(cname)

		im.PushStyleColorImVec4(.HeaderHovered, {0, 0, 0, 0})
		im.PushStyleColorImVec4(.HeaderActive, {0, 0, 0, 0})
		defer im.PopStyleColor(2)

		pos := im.GetCursorScreenPos()
		size := im.Vec2{im.GetContentRegionAvail().x, im.GetTextLineHeightWithSpacing()}
		max_pos := im.Vec2{pos.x + size.x, pos.y + size.y}
		rect_pos := im.Vec2{pos.x - 2, pos.y - 4}

		if im.IsMouseHoveringRect(pos, max_pos) {
			dl := im.GetWindowDrawList()
			im.DrawList_AddRectFilled(
				dl,
				rect_pos,
				max_pos,
				im.GetColorU32ImVec4(COLOR_MUTED_BACKGROUND),
				4.0,
				im.DrawFlags_RoundCornersAll,
			)
		}

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
						state.conn_status = .Connected
						state.latency = 0
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
						state.conn_status = .Connected
						state.latency = 0
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
			defer im.EndPopup()
			if im.MenuItem("View") {
				fill_buf(name_buf[:], conn.name)
				db_type = conn.db_type

				switch conn.db_type {
				case .Postgres:
					fill_buf(host_buf[:], conn.host)
					port = c.int(conn.port)
					fill_buf(username_buf[:], conn.username)
					ssl_enabled = conn.sql_enabled
					path_buf = {}
				case .SQLite:
					fill_buf(path_buf[:], conn.host)
					host_buf = {}
					username_buf = {}
					port = 0
				}
			}
			if im.MenuItem("Delete") {
				pending_delete = conn
				show_delete_dialog = true
			}
		}
	}

	if show_delete_dialog {
		im.OpenPopup("Delete Connection?")
		show_delete_dialog = false
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

	center_x := SIDEBAR_WIDTH + (displaySize.x - SIDEBAR_WIDTH) * 0.5
	form_pos := im.Vec2{center_x, displaySize.y * 0.5}
	Connection_Form(
		{
			state = state,
			loaded = &loaded,
			conn_error = &conn_error,
			form_pos = &form_pos,
			name_buf = &name_buf,
			host_buf = &host_buf,
			username_buf = &username_buf,
			password_buf = &password_buf,
			path_buf = &path_buf,
			port = &port,
			db_type = &db_type,
			ssl_enabled = &ssl_enabled,
			is_favorite = &is_favorite,
			connections = &connections,
			is_to_save = &is_to_save,
		},
	)
}

fill_buf :: proc(buf: []u8, s: string) {
	n := min(len(s), len(buf) - 1)
	copy(buf[:n], transmute([]u8)s[:n])
	buf[n] = 0
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
	im.PushStyleColorImVec4(.Border, COLOR_BORDER)
	im.PushStyleColorImVec4(.PopupBg, COLOR_BACKGROUND)
	defer im.PopStyleColor(2)
	defer im.PopStyleVar(3)

	if im.BeginPopupModal("Delete Connection?", nil, {.AlwaysAutoResize, .NoTitleBar, .NoMove}) {
		defer im.EndPopup()

		del_name_c := strings.clone_to_cstring(props.pending_delete.name, context.temp_allocator)
		im.PushFontFloat(FONT_MEDIUM, FONT_SIZE_BASE)
		im.Text("Delete connection?")
		im.PopFont()

		msg := fmt.tprintf("'%s' will be permanently removed.", props.pending_delete.name)
		im.TextColored(
			COLOR_MUTED_FOREGROUND,
			strings.clone_to_cstring(msg, context.temp_allocator),
		)
		im.Dummy({0, 8})

		btn_w: f32 = 80
		style := im.GetStyle()
		im.SetCursorPosX(
			im.GetWindowWidth() - style.WindowPadding.x - btn_w * 2 - style.ItemSpacing.x,
		)

		im.PushStyleVar(.FrameRounding, 4.0)
		im.PushStyleVar(.FrameBorderSize, 0.0)
		defer im.PopStyleVar(2)

		im.PushStyleColorImVec4(.Button, {0.88, 0.88, 0.90, 1.00})
		im.PushStyleColorImVec4(.ButtonHovered, {0.82, 0.82, 0.85, 1.00})
		im.PushStyleColorImVec4(.ButtonActive, {0.76, 0.76, 0.80, 1.00})
		im.PushStyleColorImVec4(.Text, {0.25, 0.25, 0.28, 1.00})
		if im.Button("Cancel", {btn_w, 0}) {
			im.CloseCurrentPopup()
		}
		im.PopStyleColor(4)

		im.SameLine()

		im.PushStyleColorImVec4(.Button, {0.98, 0.89, 0.89, 1.00})
		im.PushStyleColorImVec4(.ButtonHovered, {0.95, 0.82, 0.82, 1.00})
		im.PushStyleColorImVec4(.ButtonActive, {0.91, 0.74, 0.74, 1.00})
		im.PushStyleColorImVec4(.Text, {0.72, 0.18, 0.18, 1.00})
		if im.Button("Delete", {btn_w, 0}) {
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
		im.PopStyleColor(4)
	}
}

Connection_FormProps :: struct {
	state:        ^App_State,
	loaded:       ^bool,
	conn_error:   ^string,
	form_pos:     ^im.Vec2,
	name_buf:     ^[256]u8,
	host_buf:     ^[256]u8,
	username_buf: ^[256]u8,
	password_buf: ^[256]u8,
	path_buf:     ^[256]u8,
	port:         ^c.int,
	db_type:      ^Database_Type,
	ssl_enabled:  ^bool,
	is_favorite:  ^bool,
	connections:  ^[]Connection,
	is_to_save:   ^bool,
}

Connection_Form :: proc(props: Connection_FormProps) {
	im.SetNextWindowPos(props.form_pos^, .Always, {0.5, 0.5})
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
	im.PushStyleColorImVec4(.FrameBg, COLOR_BACKGROUND)
	im.PushStyleColorImVec4(.FrameBgHovered, COLOR_MUTED_BACKGROUND)
	im.PushStyleColorImVec4(.FrameBgActive, COLOR_MUTED_BACKGROUND)
	im.PushStyleColorImVec4(.Border, COLOR_BORDER)
	defer im.PopStyleVar(3)
	defer im.PopStyleColor(4)

	im.TextDisabled("Name")
	im.SetNextItemWidth(-1)
	im.InputText("##name", cast(cstring)&props.name_buf[0], len(props.name_buf))

	db_type_labels := [Database_Type]cstring {
		.Postgres = "postgres",
		.SQLite   = "sqlite",
	}

	im.Spacing()
	im.PushFontFloat(FONT_REGULAR, FONT_SIZE_SM)
	im.TextDisabled("Database Type")
	im.PopFont()
	im.SetNextItemWidth(-1)
	db_type_combo := im.BeginCombo("##db_type", db_type_labels[props.db_type^], {.NoArrowButton})
	{
		item_min := im.GetItemRectMin()
		item_max := im.GetItemRectMax()
		frame_h := im.GetFrameHeight()
		padding := im.GetStyle().FramePadding
		chevron_buf: [5]u8
		im.DrawList_AddTextImFontPtr(
			im.GetWindowDrawList(),
			FONT_ICONS,
			ICON_SIZE,
			{item_max.x - frame_h + padding.x, item_min.y + padding.y},
			im.GetColorU32ImVec4(COLOR_MUTED_FOREGROUND),
			icon_str(.ChevronDown, &chevron_buf),
		)
	}

	if db_type_combo {
		for label, t in db_type_labels {
			if im.Selectable(label, props.db_type^ == t) {
				props.db_type^ = t
			}
		}
		im.EndCombo()
	}

	#partial switch props.db_type^ {
	case .SQLite:
		im.Spacing()
		im.PushFontFloat(FONT_REGULAR, FONT_SIZE_SM)
		im.TextDisabled("Path")
		im.PopFont()
		browse_lbl: cstring = "Browse..."
		style := im.GetStyle()
		browse_w := im.CalcTextSize(browse_lbl).x + style.FramePadding.x * 2 + style.ItemSpacing.x
		im.SetNextItemWidth(-browse_w)
		im.InputText("##path", cast(cstring)&props.path_buf[0], len(props.path_buf))
		im.SameLine()

		if im.Button(browse_lbl) {
			path := pick_file("Select SQLite Database")
			if path != "" {
				n := min(len(path), len(props.path_buf) - 1)
				copy(props.path_buf[:n], transmute([]u8)path[:n])
				props.path_buf[n] = 0
			}
		}

	case .Postgres:
		im.Spacing()
		im.PushFontFloat(FONT_REGULAR, FONT_SIZE_SM)
		im.TextDisabled("Host")
		im.PopFont()
		im.SetNextItemWidth(-1)
		im.InputText("##host", cast(cstring)&props.host_buf[0], len(props.host_buf))

		im.Spacing()
		im.PushFontFloat(FONT_REGULAR, FONT_SIZE_SM)
		im.TextDisabled("Port")
		im.PopFont()
		im.SetNextItemWidth(-1)
		im.InputInt("##port", props.port, 0, 0)

		im.Spacing()
		im.PushFontFloat(FONT_REGULAR, FONT_SIZE_SM)
		im.TextDisabled("Username")
		im.PopFont()
		im.SetNextItemWidth(-1)
		im.InputText("##username", cast(cstring)&props.username_buf[0], len(props.username_buf))

		im.Spacing()
		im.PushFontFloat(FONT_REGULAR, FONT_SIZE_SM)
		im.TextDisabled("Password")
		im.PopFont()
		im.SetNextItemWidth(-1)
		im.InputText(
			"##password",
			cast(cstring)&props.password_buf[0],
			len(props.password_buf),
			{.Password},
		)

		im.Spacing()
		im.Checkbox("SSL Enabled", props.ssl_enabled)
	}

	im.Checkbox("Favorite", props.is_favorite)
	im.Checkbox("Save DB", props.is_to_save)
	if props.conn_error^ != "" {
		cerr := strings.clone_to_cstring(props.conn_error^)
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
				secret_key = strings.clone_from(cast(cstring)&props.password_buf[0]),
			},
			conn  = &New_Connection {
				name = strings.clone_from(cast(cstring)&props.name_buf[0]),
				db_type = props.db_type^,
				host = strings.clone_from(
					cast(cstring)(&props.path_buf[0] if props.db_type^ == .SQLite else &props.host_buf[0]),
				),
				port = int(props.port^),
				username = strings.clone_from(cast(cstring)&props.username_buf[0]),
				ssl_enabled = props.ssl_enabled^,
				is_favorite = props.is_favorite^,
			},
		}

		if props.is_to_save^ {
			err := save_db_connection(props.state.app_db, &new_conn)
			if err != nil {
				im.OpenPopup("Error")
			}
		}

		#partial switch props.db_type^ {
		case .Postgres:
			pg_conn, conn_err := pg_connect(new_conn)

			if conn_err == nil {
				props.state.conn = pg_conn
				props.state.conn_status = .Connected
				props.state.latency = 0
				props.conn_error^ = ""
				props.loaded^ = false
				props.state.db_needs_reload = true
				props.state.screen = .DatabaseViewScreen

			} else {
				props.conn_error^ = conn_err.(DB_OpenFailed).message
				log.errorf("connect failed: %s", props.conn_error^)
			}
		case .SQLite:
			sq_conn, conn_err := sqlite_connect(new_conn)
			if conn_err == nil {
				props.state.conn = sq_conn
				props.state.conn_status = .Connected
				props.state.latency = 0
				props.conn_error^ = ""
				props.loaded^ = false
				props.state.db_needs_reload = true
				props.state.screen = .DatabaseViewScreen
			} else {
				props.conn_error^ = conn_err.(DB_OpenFailed).message
				log.errorf("connect failed: %s", props.conn_error^)
			}
		}
	}
}
