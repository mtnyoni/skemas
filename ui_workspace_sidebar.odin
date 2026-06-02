package main

import "core:fmt"
import "core:strings"
import "core:time"
import im "vendor/odin-imgui"

Workspace_SidebarProps :: struct {
	state:                ^App_State,
	display_h:            f32,
	loaded_dbs:           ^[]string,
	dbs_loaded:           ^bool,
	selected_db:          ^string,
	prev_selected_db:     ^string,
	loaded_schemas:       ^[]string,
	schemas_loaded:       ^bool,
	selected_schema:      ^string,
	prev_selected_schema: ^string,
	db_schemas:           ^map[string][]string,
	db_schemas_loaded:    ^bool,
	loaded_tables:        ^[]string,
	tables_loaded:        ^bool,
	selected_table:       ^string,
	query_result:         ^QueryResult,
	prev_selected_table:  ^string,
	query_time_ms:        ^f64,
	pg_major_version:     ^i32,
}

Workspace_Sidebar :: proc(props: Workspace_SidebarProps) {
	switch conn in props.state.conn {
	case PQ_Conn:
		pg_conn := conn

		if !props.dbs_loaded^ || props.state.db_needs_reload {
			dbs, err := pg_get_dbs(pg_conn)
			if err != nil {panic(err.(DB_OpenFailed).message)}
			props.loaded_dbs^ = dbs
			props.dbs_loaded^ = true
			props.state.db_needs_reload = false
			props.pg_major_version^ = pg_server_version_major(pg_conn)
			props.state.encoding = pg_client_encoding(pg_conn)
			props.state.read_only = pg_is_read_only(pg_conn)
			current_db := pg_current_db(pg_conn)
			props.selected_db^ =
				current_db if current_db != "" else (props.loaded_dbs^[0] if len(props.loaded_dbs^) > 0 else "")
			props.prev_selected_db^ = props.selected_db^
			props.schemas_loaded^ = false
			props.selected_schema^ = ""
			props.prev_selected_schema^ = ""
			props.loaded_tables^ = {}
			props.tables_loaded^ = false
			props.selected_table^ = ""
			props.query_result^ = {}
			props.prev_selected_table^ = ""
			props.db_schemas_loaded^ = false
			delete(props.db_schemas^)
			props.db_schemas^ = {}
		}

		if !props.db_schemas_loaded^ && len(props.loaded_dbs^) > 0 {
			props.db_schemas^ = pg_get_all_db_schemas(pg_conn, props.loaded_dbs^)
			props.db_schemas_loaded^ = true
		}

		if props.selected_db^ != props.prev_selected_db^ {
			new_conn, err := pg_connect_to_db(pg_conn, props.selected_db^)
			if err == nil {
				props.state.conn = new_conn
				pg_conn = new_conn
				props.schemas_loaded^ = false
			} else {
				props.loaded_schemas^ = {}
				props.schemas_loaded^ = true
			}
			props.selected_schema^ = ""
			props.prev_selected_schema^ = ""
			props.loaded_tables^ = {}
			props.tables_loaded^ = false
			props.selected_table^ = ""
			props.query_result^ = {}
			props.prev_selected_table^ = ""
			props.prev_selected_db^ = props.selected_db^
		}

		if !props.schemas_loaded^ {
			schemas, err := pg_get_schemas(pg_conn)
			if err == nil {
				props.loaded_schemas^ = schemas
				props.schemas_loaded^ = true
				props.selected_schema^ =
					props.loaded_schemas^[0] if len(props.loaded_schemas^) > 0 else ""
			}
		}

		if props.selected_schema^ != props.prev_selected_schema^ {
			props.loaded_tables^ = {}
			props.tables_loaded^ = false
			props.selected_table^ = ""
			props.query_result^ = {}
			props.prev_selected_table^ = ""
			if props.selected_schema^ != "" {
				tables, err := pg_get_tables(pg_conn, props.selected_schema^)
				if err == nil {
					props.loaded_tables^ = tables
					props.tables_loaded^ = true
				}
			}
			props.prev_selected_schema^ = props.selected_schema^
		}

		if props.selected_table^ != props.prev_selected_table^ {
			props.query_result^ = {}
			props.query_time_ms^ = 0
			if props.selected_table^ != "" && props.selected_schema^ != "" {
				q := fmt.tprintf(
					`SELECT * FROM "%s"."%s" LIMIT 1000`,
					props.selected_schema^,
					props.selected_table^,
				)
				t := time.tick_now()
				result, err := pg_run_query(pg_conn, q)
				props.query_time_ms^ = time.duration_milliseconds(time.tick_since(t))
				if err == nil {props.query_result^ = result}
			}
			props.prev_selected_table^ = props.selected_table^
		}

	case SQLite_Conn:
		sq_conn := conn

		if !props.tables_loaded^ || props.state.db_needs_reload {
			props.state.db_needs_reload = false
			props.loaded_tables^ = sqlite_get_tables(sq_conn)
			props.tables_loaded^ = true
			props.selected_table^ = ""
			props.query_result^ = {}
			props.prev_selected_table^ = ""
		}

		if props.selected_table^ != props.prev_selected_table^ {
			props.query_result^ = {}
			props.query_time_ms^ = 0
			if props.selected_table^ != "" {
				q := fmt.tprintf(`SELECT * FROM "%s" LIMIT 1000`, props.selected_table^)
				t := time.tick_now()
				result, err := sqlite_run_query(sq_conn, q)
				props.query_time_ms^ = time.duration_milliseconds(time.tick_since(t))
				if err == nil {props.query_result^ = result}
			}
			props.prev_selected_table^ = props.selected_table^
		}
	}

	// Shared sidebar window
	im.SetNextWindowPos({0, 0}, .Always)
	im.SetNextWindowSize({SIDEBAR_WIDTH, props.display_h - WORKSPACE_STATUS_BAR_H}, .Always)
	im.PushStyleVar(.WindowBorderSize, 0)
	defer im.PopStyleVar()
	im.Begin("##sidebar", nil, {.NoMove, .NoResize, .NoCollapse, .NoScrollbar, .NoTitleBar})
	defer im.End()

	DB_Servers_Select(
		{
			schemas_loaded = props.schemas_loaded,
			prev_selected_schema = props.prev_selected_schema,
			selected_schema = props.selected_schema,
			loaded_schemas = props.loaded_schemas,
			tables_loaded = props.tables_loaded,
			selected_table = props.selected_table,
			prev_selected_table = props.prev_selected_table,
			loaded_tables = props.loaded_tables,
			query_result = props.query_result,
			query_time_ms = props.query_time_ms,
			pg_major_version = props.pg_major_version,
			state = props.state,
		},
	)

	// Connection-specific UI
	switch conn in props.state.conn {
	case PQ_Conn:
		draw_db_schema_dropdown(
			props.loaded_dbs^,
			props.db_schemas^,
			props.selected_db,
			props.selected_schema,
		)

		im.Spacing()
		im.PushFontFloat(FONT_REGULAR, FONT_SIZE_BASE)
		im.TextDisabled("Tables")
		im.PopFont()

		im.PushFontFloat(FONT_REGULAR, FONT_SIZE_XS)
		count_lbl := strings.clone_to_cstring(
			fmt.tprintf("%d", len(props.loaded_tables^)),
			context.temp_allocator,
		)
		count_w := im.CalcTextSize(count_lbl).x
		im.SameLine(im.GetWindowWidth() - im.GetStyle().WindowPadding.x - count_w)
		im.PushStyleColorImVec4(.Text, COLOR_MUTED_FOREGROUND)
		im.TextUnformatted(count_lbl)
		im.PopStyleColor()
		im.PopFont()

		im.PushStyleVar(.ChildRounding, 4)
		defer im.PopStyleVar()

		im.BeginChild("##tables_list", {-1, -1}, {.Borders})
		for tbl in props.loaded_tables^ {
			cname := strings.clone_to_cstring(tbl)
			defer delete(cname)
			if im.Selectable(cname, props.selected_table^ == tbl) {
				props.selected_table^ = tbl
			}
		}
		im.EndChild()

	case SQLite_Conn:
		im.PushFontFloat(FONT_REGULAR, FONT_SIZE_BASE)
		im.TextDisabled("Tables")
		im.PopFont()

		sq_count_lbl := strings.clone_to_cstring(
			fmt.tprintf("%d", len(props.loaded_tables^)),
			context.temp_allocator,
		)
		sq_count_w := im.CalcTextSize(sq_count_lbl).x
		im.SameLine(im.GetWindowWidth() - im.GetStyle().WindowPadding.x - sq_count_w)
		im.PushFontFloat(FONT_REGULAR, FONT_SIZE_XS)
		im.PushStyleColorImVec4(.Text, COLOR_MUTED_FOREGROUND)
		im.TextUnformatted(sq_count_lbl)
		im.PopStyleColor()
		im.PopFont()

		im.BeginChild("##tables_list", {-1, -1}, {.Borders})
		for tbl in props.loaded_tables^ {
			cname := strings.clone_to_cstring(tbl)
			defer delete(cname)
			if im.Selectable(cname, props.selected_table^ == tbl) {
				props.selected_table^ = tbl
			}

			if props.selected_table^ == tbl {
				row_count_lbl := strings.clone_to_cstring(
					fmt.tprintf("%d", len(props.query_result^.rows)),
					context.temp_allocator,
				)
				im.PushFontFloat(FONT_REGULAR, FONT_SIZE_XS)
				row_count_w := im.CalcTextSize(row_count_lbl).x
				im.SameLine(im.GetWindowWidth() - im.GetStyle().WindowPadding.x * 2 - row_count_w)
				im.PushStyleColorImVec4(.Text, COLOR_MUTED_FOREGROUND)
				im.TextUnformatted(row_count_lbl)
				im.PopStyleColor()
				im.PopFont()
			}
		}
		im.EndChild()
	}

	im.DrawList_AddLine(
		im.GetForegroundDrawList(),
		{SIDEBAR_WIDTH, 0},
		{SIDEBAR_WIDTH, props.display_h - WORKSPACE_STATUS_BAR_H},
		im.GetColorU32(.Separator),
		1.0,
	)
}

DB_SCHEMA_POPUP_NAME :: "##db_schema_dual_popup"

draw_db_schema_dropdown :: proc(
	loaded_dbs: []string,
	db_schemas: map[string][]string,
	selected_db: ^string,
	selected_schema: ^string,
) {
	@(static) hovered_db: string

	label_buf: [256]byte
	label_str: string
	if selected_db^ != "" && selected_schema^ != "" {
		label_str = fmt.bprintf(label_buf[:], "%s · %s", selected_db^, selected_schema^)
	} else {
		label_str = "Select database & schema..."
	}
	clabel := strings.clone_to_cstring(label_str, context.temp_allocator)

	im.SetNextItemWidth(-1)
	im.PushStyleVar(.FrameBorderSize, 1.0)
	im.PushStyleVar(.FrameRounding, 4)
	im.PushStyleVarImVec2(.ButtonTextAlign, {0.0, 0.5})
	im.PushStyleColorImVec4(.FrameBgHovered, COLOR_MUTED_BACKGROUND)
	im.PushStyleColorImVec4(.Button, COLOR_BACKGROUND)
	im.PushStyleColorImVec4(.ButtonHovered, COLOR_MUTED_BACKGROUND)
	im.PushStyleColorImVec4(.ButtonActive, COLOR_MUTED_BACKGROUND)

	if im.Button(clabel, {-1, 0}) {
		im.OpenPopup(DB_SCHEMA_POPUP_NAME)
	}
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
	im.PopStyleColor(4)
	im.PopStyleVar(3)

	btn_min := im.GetItemRectMin()
	btn_max := im.GetItemRectMax()
	im.SetNextWindowPos({btn_min.x, btn_max.y + 2}, .Always)
	im.SetNextWindowSize({600, 280}, .Always)
	im.PushStyleVarImVec2(.WindowPadding, {12, 12})
	im.PushStyleColorImVec4(.PopupBg, COLOR_BACKGROUND)

	if im.BeginPopup(DB_SCHEMA_POPUP_NAME) {
		im.PopStyleVar() // WindowPadding
		im.PopStyleColor() // PopupBg

		if hovered_db == "" && len(loaded_dbs) > 0 {
			hovered_db = selected_db^ != "" ? selected_db^ : loaded_dbs[0]
		}

		im.Columns(2, "##db_schema_cols", true)
		im.SetColumnWidth(0, 200)

		im.TextDisabled("DATABASES")
		im.Separator()
		im.Spacing()
		for db in loaded_dbs {
			cname := strings.clone_to_cstring(db, context.temp_allocator)
			if im.Selectable(cname, hovered_db == db, {.AllowOverlap}) {
				if db != selected_db^ {
					selected_db^ = db
					selected_schema^ = ""
					hovered_db = db
					im.CloseCurrentPopup()
				} else {
					hovered_db = db
				}
			}
			if im.IsItemHovered() {
				hovered_db = db
			}
		}

		im.NextColumn()
		active_schemas := db_schemas[hovered_db] if hovered_db in db_schemas else []string{}

		schema_title := fmt.tprintf("%d SCHEMAS", len(active_schemas))
		im.TextDisabled(strings.clone_to_cstring(schema_title, context.temp_allocator))
		im.Separator()
		im.Spacing()

		if len(active_schemas) == 0 && hovered_db != selected_db^ {
			im.TextDisabled("Click to switch database")
		}

		for s, i in active_schemas {
			cs := strings.clone_to_cstring(s, context.temp_allocator)
			is_selected := selected_db^ == hovered_db && selected_schema^ == s

			start_pos_x := im.GetCursorPosX()

			if im.Selectable(cs, is_selected) {
				selected_db^ = hovered_db
				selected_schema^ = s
				hovered_db = ""
				im.CloseCurrentPopup()
			}
			if i == 0 {
				im.SameLine()
				right_align_x := start_pos_x + im.GetContentRegionAvail().x - 45
				im.SetCursorPosX(right_align_x)
				im.TextDisabled("default")
			}
		}

		im.Columns(1)
		im.EndPopup()
	} else {
		im.PopStyleVar()
		im.PopStyleColor()
	}
}

DB_Servers_SelectProps :: struct {
	schemas_loaded:       ^bool,
	prev_selected_schema: ^string,
	selected_schema:      ^string,
	loaded_schemas:       ^[]string,
	tables_loaded:        ^bool,
	selected_table:       ^string,
	prev_selected_table:  ^string,
	loaded_tables:        ^[]string,
	query_result:         ^QueryResult,
	query_time_ms:        ^f64,
	pg_major_version:     ^i32,
	state:                ^App_State,
}

DB_Servers_Select :: proc(props: DB_Servers_SelectProps) {
	@(static) connections: []Connection
	@(static) connections_loaded: bool
	@(static) active_conn_name: string

	if !connections_loaded {
		conns, err := get_connections(props.state.app_db)
		if err == nil {
			connections = conns
		}
		connections_loaded = true
	}

	im.TextDisabled("Servers")
	conn_label := strings.clone_to_cstring(
		active_conn_name if active_conn_name != "" else "Select connection...",
		context.temp_allocator,
	)

	im.SetNextItemWidth(-1)
	im.PushStyleVar(.FrameBorderSize, 1.0)
	im.PushStyleVar(.FrameRounding, 4)
	defer im.PopStyleVar(2)
	im.PushStyleColorImVec4(.FrameBgHovered, COLOR_MUTED_BACKGROUND)
	defer im.PopStyleColor()

	combo_open := im.BeginCombo("##db_servers_select", conn_label, {.NoArrowButton})
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

	if combo_open {
		for conn in connections {
			cname := strings.clone_to_cstring(conn.name, context.temp_allocator)
			if im.Selectable(cname, active_conn_name == conn.name) &&
			   conn.name != active_conn_name {
				cred, cred_err := get_credential(props.state.app_db, conn.credential_id)
				if cred_err != nil {im.EndCombo(); return}

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

				// Reset shared state
				props.state.conn_status = .Connecting
				props.tables_loaded^ = false
				props.selected_table^ = ""
				props.prev_selected_table^ = ""
				props.loaded_tables^ = nil
				props.query_result^ = {}
				props.query_time_ms^ = 0

				// Reset Postgres-only state
				if conn.db_type == .Postgres {
					props.schemas_loaded^ = false
					props.prev_selected_schema^ = ""
					props.selected_schema^ = ""
					props.loaded_schemas^ = nil
					props.pg_major_version^ = 0
				}

				switch conn.db_type {
				case .Postgres:
					pg_conn, err := pg_connect(params)
					if err == nil {
						props.state.conn = pg_conn
						props.state.db_needs_reload = true
						active_conn_name = conn.name
					} else {
						props.state.conn_status = .Disconnected
					}

				case .SQLite:
					sq_conn, err := sqlite_connect(params)
					if err == nil {
						props.state.conn = sq_conn
						props.state.db_needs_reload = true
						active_conn_name = conn.name
					} else {
						props.state.conn_status = .Disconnected
					}
				}
			}
		}

		im.EndCombo()
	}
}
